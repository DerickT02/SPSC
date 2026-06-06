# spsc-queue

Lock-free single-producer single-consumer queue in C++20 using acquire-release atomics. A deliberate study in the C++ memory model, cache-line discipline, and zero-copy data transfer without mutexes.

---

## What this is

A ground-up implementation of an SPSC ring buffer — the simplest correct lock-free data structure. One thread writes, one thread reads, no locks anywhere. The goal is to understand *why* each line is written the way it is, not to produce a library.

This is a learning project. Code is written by hand. AI is used only for explanation and review.

---

## Phases

### Phase 1 — Naive ring buffer (no atomics)
**Goal:** get the shape right before worrying about correctness across threads.

- Fixed-capacity ring buffer over a `T buf[N]` array
- `head` and `tail` as plain `size_t` indices
- `push(T)` returns false when full, `pop(T&)` returns false when empty
- Single-threaded test: fill to capacity, drain, verify values and order
- No heap allocation — everything lives on the stack or as a member

**What you learn:** the modular index pattern, how capacity-1 or a separate size counter handles the full/empty ambiguity, and why a power-of-two capacity lets you replace `% N` with `& (N-1)`.

---

### Phase 2 — Add `std::atomic` with sequential consistency
**Goal:** make it technically correct for two threads, even if not optimal.

- Change `head` and `tail` to `std::atomic<size_t>`
- Use default `memory_order_seq_cst` on all loads and stores
- Write a two-thread test: producer pushes 1M integers, consumer reads them, verify sum
- Measure throughput with `std::chrono`

**What you learn:** why the naive version is UB under the C++ memory model, what a data race formally is, and what `seq_cst` actually buys you (a total order over all atomic operations — expensive on x86, very expensive on ARM).

---

### Phase 3 — Relax to acquire-release
**Goal:** understand *why* acquire-release is sufficient for SPSC and where it saves you.

- Change the producer's `tail` store to `memory_order_release`
- Change the consumer's `tail` load to `memory_order_acquire`
- Same for `head` on the consumer side
- Re-run the two-thread test — verify it still passes
- Benchmark against Phase 2 and observe the throughput difference (more visible on ARM than x86)

**What you learn:** the release-acquire handshake — a store with `release` "publishes" all prior writes to any thread that subsequently does an `acquire` load of the same variable. This is the exact pattern needed: the producer publishes the slot's data before advancing `tail`, the consumer acquires `tail` before reading the slot.

**Key question to answer yourself before moving on:** why is `relaxed` wrong here, even though there's only one writer and one reader?

---

### Phase 4 — Cache-line discipline
**Goal:** eliminate false sharing between producer and consumer.

- `head` and `tail` are currently adjacent in memory — they share a cache line
- The producer writes `tail` and reads `head`; the consumer writes `head` and reads `tail`
- This causes cache-line ping-pong between cores even though they touch different variables
- Fix: align each to its own 64-byte cache line using `alignas(64)`
- Also align the buffer itself to avoid straddling lines on the first element
- Re-benchmark — this is often a 2–5x throughput improvement

**What you learn:** false sharing, `alignas`, and why the physical layout of your struct matters as much as the algorithm. This is the difference between "correct" and "fast."

---

### Phase 5 — Batch operations & throughput optimization
**Goal:** push throughput closer to the memory bandwidth ceiling.

- Add `push_batch(T* src, size_t count)` and `pop_batch(T* dst, size_t count)` — write/read a contiguous chunk in one operation, advancing the index once
- Use `std::memcpy` for trivially copyable types
- Add a `size_approx()` that reads `tail - head` with relaxed ordering (fine for a non-authoritative estimate)
- Benchmark batch vs single-element at varying payload sizes

**What you learn:** amortizing the atomic operation cost over N elements, the difference between `memcpy` throughput and per-element overhead, and when `std::is_trivially_copyable` matters.

---

### Phase 6 — Generics, concepts, and move support
**Goal:** make it a real C++20 template.

- Templatize on `T` and `N` (capacity as a non-type template parameter)
- Add a `static_assert` that `N` is a power of two
- Add a concept constraint: `T` must be `std::movable`
- Support `push(T&&)` with `std::move` into the slot — no unnecessary copies
- Add a `try_push` / `try_pop` pair returning `std::optional<T>`
- Ensure the destructor properly destroys unconsumed elements

**What you learn:** non-type template parameters, `static_assert` for compile-time validation, placement new for in-place construction in the ring buffer, and how `std::optional` replaces output parameters.

---

### Phase 7 — Benchmarking & profiling
**Goal:** connect implementation decisions to measurable outcomes.

- Write a microbenchmark using Google Benchmark or a manual `rdtsc`-based timer
- Measure: latency per operation (ns), throughput (ops/sec), cache miss rate (`perf stat`)
- Compare against `std::mutex` + `std::queue` to quantify the lock-free advantage
- Profile with `perf record` + `perf report` — identify the hottest instructions
- Try varying: payload size, capacity, CPU affinity (pin producer/consumer to specific cores)

**What you learn:** how to benchmark without fooling yourself (compiler barriers, `DoNotOptimize`), how to read `perf` output, and why CPU affinity and NUMA topology matter for this class of problem.

---

## Reference reading

- Herb Sutter — "atomic Weapons" (CppCon 2012) — the definitive talk on the C++ memory model
- Martin Thompson — LMAX Disruptor architecture post — the production version of this idea
- Jeff Preshing — preshing.com — every post on lock-free programming, especially "Acquire and Release Semantics"
- `linux/kfifo.h` in the kernel source — read it after Phase 3; it's the same algorithm in C

---

## Non-goals

- This is not a production library. Use Folly's `ProducerConsumerQueue` or `rigtorp/SPSCQueue` for that.
- No MPMC, no dynamic sizing, no allocator support — those are separate problems.

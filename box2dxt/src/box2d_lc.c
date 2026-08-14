/*
 * box2d_lc.c
 * ----------------------------------------------------------------------------
 * The C shim at the heart of Box2Dxt: a thin layer that exposes Box2D v3 to
 * xTalk Builder (LCB) via its foreign function interface (FFI), so OpenXTalk /
 * LiveCode-compatible engines can drive a real physics engine.
 *
 * Why a shim is needed even though Box2D v3 is already C:
 *   - Box2D v3 identifiers (b2WorldId, b2BodyId, ...) are small structs passed
 *     BY VALUE. The LCB FFI is happiest with plain scalars and pointers, and
 *     there is no 64-bit integer foreign type. So every Box2D id is stored in a
 *     shim-side handle table and crosses the FFI boundary as a positive 32-bit
 *     int handle (0 means null / invalid). Handles are generation-tagged, so a
 *     handle stays dead after its object is destroyed even once the table slot
 *     is recycled; treat them as opaque.
 *   - Every real number crosses as `double` (xTalk numbers are doubles);
 *     internally we cast to/from Box2D's `float`.
 *   - Every boolean crosses as `int` (0 / 1).
 *
 * Safety: every handle is validated with Box2D's generation-checked
 * b2*_IsValid() before use. Calling any handler with a stale or never-created
 * handle is therefore a harmless no-op (getters return 0) rather than a crash.
 * The integer handle of each body/shape is also stored in its Box2D userData so
 * queries, ray casts and contact events can hand a handle back to the script.
 *
 * The exported C ABI symbols use the historical "b2lc_" prefix; it is kept
 * stable across the OpenXTalk rebrand so existing compiled binaries keep working.
 *
 * Build: compiled together with Box2D v3.1.0 into ONE shared library named
 * "box2dxt" (libbox2dxt.so / libbox2dxt.dylib / box2dxt.dll). See CMakeLists.txt.
 *
 * Verified to compile and link against Box2D v3.1.0.
 * ----------------------------------------------------------------------------
 */

#include "box2d/box2d.h"

#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <math.h>

#if !defined(_WIN32)
    #include <pthread.h>
    #include <unistd.h>
#endif

#if defined(_WIN32)
    #define LC_API __declspec(dllexport)
#else
    #define LC_API __attribute__((visibility("default")))
#endif

/* Bump when the exported ABI changes so the LCB side can sanity-check. */
#define LC_ABI_VERSION 4

/* ------------------------------------------------------------------ */
/* Generic handle tables. Handles are positive ints; 0 == null/invalid.*/
/* Freed slots are recycled via a free list so create/destroy churn    */
/* does not grow memory without bound.                                 */
/*                                                                     */
/* Each handle packs an 11-bit generation above a 20-bit slot number   */
/* (low 20 bits = slot + 1, so a handle is never 0 and the first       */
/* generation yields the familiar small values 1, 2, 3, ...). The slot */
/* generation bumps every time the slot is freed, so a stale handle    */
/* kept by script code stays DEAD after its slot is recycled instead   */
/* of silently aliasing whatever object lives there next. Box2D's own  */
/* ids are generation-checked for exactly this reason; the table must  */
/* not undo that protection. A false match needs the same slot reused  */
/* 2048 times while the stale handle is still around.                  */
/* ------------------------------------------------------------------ */
#define LC_H_SLOT_BITS 20
#define LC_H_SLOT_MASK 0xFFFFF            /* low 20 bits: slot + 1     */
#define LC_H_GEN_MASK  0x7FF              /* 11 bits of generation     */
#define LC_H_MAX_SLOTS (LC_H_SLOT_MASK - 1)

#define DEFINE_TABLE(NAME, TYPE)                                              \
    static TYPE *NAME##_arr = NULL;                                           \
    static unsigned char  *NAME##_used = NULL;                                \
    static unsigned short *NAME##_gen = NULL;                                 \
    static int   NAME##_cap = 0;                                              \
    static int   NAME##_cnt = 0;                                              \
    static int  *NAME##_free = NULL;                                          \
    static int   NAME##_freeCap = 0;                                          \
    static int   NAME##_freeCnt = 0;                                          \
    static int NAME##_grow_slots(int nc) {                                    \
        TYPE *na = (TYPE *)realloc(NAME##_arr, (size_t)nc * sizeof(TYPE));    \
        if (!na) return 0;                                                    \
        NAME##_arr = na;                                                      \
        unsigned char *nu = (unsigned char *)realloc(NAME##_used,             \
                                                     (size_t)nc);             \
        if (!nu) return 0;                                                    \
        NAME##_used = nu;                                                     \
        unsigned short *ng = (unsigned short *)realloc(NAME##_gen,            \
                                            (size_t)nc * sizeof(short));      \
        if (!ng) return 0;                                                    \
        NAME##_gen = ng;                                                      \
        memset(NAME##_used + NAME##_cap, 0, (size_t)(nc - NAME##_cap));       \
        memset(NAME##_gen + NAME##_cap, 0,                                    \
               (size_t)(nc - NAME##_cap) * sizeof(short));                    \
        NAME##_cap = nc;                                                      \
        return 1;                                                             \
    }                                                                         \
    static int NAME##_encode(int idx) {                                       \
        return (int)(((unsigned)NAME##_gen[idx] << LC_H_SLOT_BITS)            \
                     | (unsigned)(idx + 1));                                  \
    }                                                                         \
    /* handle -> slot index, or -1 if stale / never created */               \
    static int NAME##_slot_of(int h) {                                        \
        if (h <= 0) return -1;                                                \
        int idx = (h & LC_H_SLOT_MASK) - 1;                                   \
        unsigned gen = ((unsigned)h >> LC_H_SLOT_BITS) & LC_H_GEN_MASK;       \
        if (idx < 0 || idx >= NAME##_cnt) return -1;                          \
        if (!NAME##_used[idx] || NAME##_gen[idx] != gen) return -1;           \
        return idx;                                                           \
    }                                                                         \
    static int NAME##_add(TYPE v) {                                           \
        int idx;                                                              \
        if (NAME##_freeCnt > 0) {                                             \
            do {                                                              \
                idx = NAME##_free[--NAME##_freeCnt];                          \
            } while (NAME##_freeCnt > 0 && NAME##_used[idx]);                 \
            if (NAME##_used[idx]) idx = -1;                                   \
        } else {                                                              \
            idx = -1;                                                         \
        }                                                                     \
        if (idx < 0) {                                                        \
            if (NAME##_cnt >= LC_H_MAX_SLOTS) return 0;                       \
            if (NAME##_cnt >= NAME##_cap) {                                   \
                int nc = NAME##_cap ? NAME##_cap * 2 : 64;                    \
                if (!NAME##_grow_slots(nc)) return 0;                         \
            }                                                                 \
            idx = NAME##_cnt++;                                               \
        }                                                                     \
        NAME##_arr[idx] = v;                                                  \
        NAME##_used[idx] = 1;                                                 \
        return NAME##_encode(idx);                                            \
    }                                                                         \
    static TYPE NAME##_get(int h) {                                           \
        int idx = NAME##_slot_of(h);                                          \
        if (idx < 0) { TYPE z; memset(&z, 0, sizeof z); return z; }           \
        return NAME##_arr[idx];                                               \
    }                                                                         \
    static int NAME##_free_slot(int idx) {                                    \
        if (idx < 0 || idx >= NAME##_cnt || !NAME##_used[idx]) return 0;      \
        if (NAME##_freeCnt >= NAME##_freeCap) {                               \
            int nc = NAME##_freeCap ? NAME##_freeCap * 2 : 64;                \
            int *nf = (int *)realloc(NAME##_free, (size_t)nc * sizeof(int));  \
            if (!nf) return 0;                                                \
            NAME##_free = nf; NAME##_freeCap = nc;                            \
        }                                                                     \
        { TYPE z; memset(&z, 0, sizeof z); NAME##_arr[idx] = z; }             \
        NAME##_used[idx] = 0;                                                 \
        NAME##_gen[idx] = (unsigned short)((NAME##_gen[idx] + 1)              \
                                           & LC_H_GEN_MASK);                  \
        NAME##_free[NAME##_freeCnt++] = idx;                                  \
        return 1;                                                             \
    }                                                                         \
    static int NAME##_free_handle(int h) {                                    \
        return NAME##_free_slot(NAME##_slot_of(h));                          \
    }

DEFINE_TABLE(worlds, b2WorldId)
DEFINE_TABLE(bodies, b2BodyId)
DEFINE_TABLE(shapes, b2ShapeId)
DEFINE_TABLE(joints, b2JointId)
DEFINE_TABLE(chains, b2ChainId)

/* Retire any child handles whose Box2D ids became invalid because a parent
 * object (usually a world or body) destroyed them implicitly. This keeps stale
 * ids harmless while also letting future create calls reuse their table slots. */
static void retire_invalid_child_handles(void) {
    for (int i = 0; i < bodies_cnt; i++)
        if (bodies_used[i] && !b2Body_IsValid(bodies_arr[i])) bodies_free_slot(i);
    for (int i = 0; i < shapes_cnt; i++)
        if (shapes_used[i] && !b2Shape_IsValid(shapes_arr[i])) shapes_free_slot(i);
    for (int i = 0; i < joints_cnt; i++)
        if (joints_used[i] && !b2Joint_IsValid(joints_arr[i])) joints_free_slot(i);
    for (int i = 0; i < chains_cnt; i++)
        if (chains_used[i] && !b2Chain_IsValid(chains_arr[i])) chains_free_slot(i);
}

/* small helpers */
static inline b2Vec2 v2(double x, double y) { b2Vec2 v; v.x = (float)x; v.y = (float)y; return v; }
static inline b2Rot  rotOf(double a)        { b2Rot r; r.c = (float)cos(a); r.s = (float)sin(a); return r; }
static int grow_buffer(void **buf, int *cap, int newCap, size_t elemSize) {
    if (newCap <= *cap) return 1;
    void *p = realloc(*buf, (size_t)newCap * elemSize);
    if (!p) return 0;
    *buf = p;
    *cap = newCap;
    return 1;
}
static int finite1(double a) { return isfinite(a); }
static int finite2(double a, double b) { return isfinite(a) && isfinite(b); }
static int finite3(double a, double b, double c) { return isfinite(a) && isfinite(b) && isfinite(c); }
static double nonneg_or(double v, double fallback) { return (isfinite(v) && v >= 0.0) ? v : fallback; }
static int valid_body_type(int t) { return t >= 0 && t <= 2; }
static int positive(double v) { return isfinite(v) && v > 0.0; }
/* Filter bits arrive as doubles; converting a negative or out-of-range value
 * straight to an unsigned type is undefined behaviour in C, so range-check
 * first. Doubles carry integers exactly up to 2^53, so 53 of Box2D's 64
 * category bits are usable from script. */
#define LC_FILTER_BITS_MAX 9007199254740991.0   /* 2^53 - 1 */
static int filter_bits_ok(double v) { return isfinite(v) && v >= 0.0 && v <= LC_FILTER_BITS_MAX; }

/* integer handle <-> Box2D userData (void*) round-trip */
static inline void *h2ud(int h)   { return (void *)(intptr_t)h; }
static inline int   ud2h(void *p) { return (int)(intptr_t)p; }


/* ------------------------------------------------------------------ */
/* Optional Box2D task system.                                         */
/* ------------------------------------------------------------------ */
/* Box2D v3 can parallelize a single world step if the world definition
 * provides workerCount/enqueueTask/finishTask. OXT/LC script execution stays
 * single-threaded, but the native solver can still fan out during
 * b2World_Step(). The pool below is deliberately private to the C shim: script
 * code never touches Box2D objects from worker threads, and finishTask waits
 * before control returns across the FFI boundary.
 *
 * On POSIX platforms we create workerCount-1 background pthreads and let the
 * caller thread help in finishTask as worker 0. Other platforms fall back to
 * Box2D's normal single-threaded path until a native backend is added. */
#if !defined(_WIN32)
typedef struct LcTaskPool LcTaskPool;
typedef struct LcTaskGroup LcTaskGroup;

struct LcTaskGroup {
    b2TaskCallback *task;
    void *taskContext;
    int itemCount;
    int minRange;
    int nextIndex;
    int remaining;
    int queued;
    LcTaskPool *pool;
    LcTaskGroup *next;
};

/* Each background worker gets its own arg so its Box2D worker index is fixed at
 * creation and passed by value. The previous code discovered the index by racing
 * to find pthread_self() in pool->threads[], which the worker can read before the
 * parent has finished writing the array (POSIX only guarantees the child sees
 * writes made *before* pthread_create) -- two workers could then collide on the
 * same index and stomp the same per-worker Box2D task storage. */
typedef struct LcWorkerArg {
    LcTaskPool *pool;
    uint32_t workerIndex;       /* 1..threadCount (worker 0 is the calling thread) */
} LcWorkerArg;

struct LcTaskPool {
    int workerCount;            /* total Box2D workers, including caller */
    int threadCount;            /* background workers only */
    pthread_t *threads;
    LcWorkerArg *workerArgs;    /* one per background worker; index fixed at create */
    pthread_mutex_t mutex;
    pthread_cond_t workCond;
    pthread_cond_t doneCond;
    int stopping;
    LcTaskGroup *head;
    LcTaskGroup *tail;
};

static int lc_task_chunk_count(int itemCount, int minRange) {
    if (itemCount <= 0) return 0;
    if (minRange < 1) minRange = 1;
    return (itemCount + minRange - 1) / minRange;
}

static void lc_task_unqueue_locked(LcTaskPool *pool, LcTaskGroup *group, LcTaskGroup *prev) {
    if (!group->queued) return;
    if (prev) prev->next = group->next; else pool->head = group->next;
    if (pool->tail == group) pool->tail = prev;
    group->next = NULL;
    group->queued = 0;
}

static int lc_task_take_locked(LcTaskPool *pool, LcTaskGroup *group, int *start, int *end) {
    if (group->nextIndex >= group->itemCount) return 0;
    *start = group->nextIndex;
    *end = *start + group->minRange;
    if (*end > group->itemCount) *end = group->itemCount;
    group->nextIndex = *end;
    if (group->nextIndex >= group->itemCount && group->queued) {
        LcTaskGroup *prev = NULL;
        for (LcTaskGroup *g = pool->head; g; g = g->next) {
            if (g == group) { lc_task_unqueue_locked(pool, group, prev); break; }
            prev = g;
        }
    }
    return 1;
}

static void lc_task_complete_locked(LcTaskPool *pool, LcTaskGroup *group) {
    group->remaining -= 1;
    if (group->remaining <= 0) pthread_cond_broadcast(&pool->doneCond);
}

static void *lc_task_worker(void *arg) {
    LcWorkerArg *wa = (LcWorkerArg *)arg;
    LcTaskPool *pool = wa->pool;
    uint32_t workerIndex = wa->workerIndex;   /* fixed at create; no self-search race */

    for (;;) {
        pthread_mutex_lock(&pool->mutex);
        while (!pool->stopping && pool->head == NULL) pthread_cond_wait(&pool->workCond, &pool->mutex);
        if (pool->stopping) { pthread_mutex_unlock(&pool->mutex); break; }
        LcTaskGroup *group = pool->head;
        int start = 0, end = 0;
        int have = lc_task_take_locked(pool, group, &start, &end);
        pthread_mutex_unlock(&pool->mutex);

        if (have) {
            group->task(start, end, workerIndex, group->taskContext);
            pthread_mutex_lock(&pool->mutex);
            lc_task_complete_locked(pool, group);
            pthread_mutex_unlock(&pool->mutex);
        }
    }
    return NULL;
}

static LcTaskPool *lc_task_pool_create(int workerCount) {
    if (workerCount < 2) return NULL;
    int online = (int)sysconf(_SC_NPROCESSORS_ONLN);
    if (online > 0 && workerCount > online) workerCount = online;
    if (workerCount < 2) return NULL;
    if (workerCount > 32) workerCount = 32;

    LcTaskPool *pool = (LcTaskPool *)calloc(1, sizeof(LcTaskPool));
    if (!pool) return NULL;
    pool->workerCount = workerCount;
    pool->threadCount = workerCount - 1;
    pool->threads = (pthread_t *)calloc((size_t)pool->threadCount, sizeof(pthread_t));
    pool->workerArgs = (LcWorkerArg *)calloc((size_t)pool->threadCount, sizeof(LcWorkerArg));
    if (!pool->threads || !pool->workerArgs) { free(pool->workerArgs); free(pool->threads); free(pool); return NULL; }
    if (pthread_mutex_init(&pool->mutex, NULL) != 0) { free(pool->workerArgs); free(pool->threads); free(pool); return NULL; }
    if (pthread_cond_init(&pool->workCond, NULL) != 0 || pthread_cond_init(&pool->doneCond, NULL) != 0) {
        pthread_mutex_destroy(&pool->mutex); free(pool->workerArgs); free(pool->threads); free(pool); return NULL;
    }
    for (int i = 0; i < pool->threadCount; i++) {
        pool->workerArgs[i].pool = pool;
        pool->workerArgs[i].workerIndex = (uint32_t)(i + 1);   /* fixed before the thread starts */
        if (pthread_create(&pool->threads[i], NULL, lc_task_worker, &pool->workerArgs[i]) != 0) {
            pthread_mutex_lock(&pool->mutex);
            pool->stopping = 1;
            pthread_cond_broadcast(&pool->workCond);
            pthread_mutex_unlock(&pool->mutex);
            for (int j = 0; j < i; j++) pthread_join(pool->threads[j], NULL);
            pthread_cond_destroy(&pool->doneCond); pthread_cond_destroy(&pool->workCond);
            pthread_mutex_destroy(&pool->mutex); free(pool->workerArgs); free(pool->threads); free(pool);
            return NULL;
        }
    }
    return pool;
}

static void lc_task_pool_destroy(LcTaskPool *pool) {
    if (!pool) return;
    pthread_mutex_lock(&pool->mutex);
    pool->stopping = 1;
    pthread_cond_broadcast(&pool->workCond);
    pthread_mutex_unlock(&pool->mutex);
    for (int i = 0; i < pool->threadCount; i++) pthread_join(pool->threads[i], NULL);
    pthread_cond_destroy(&pool->doneCond);
    pthread_cond_destroy(&pool->workCond);
    pthread_mutex_destroy(&pool->mutex);
    free(pool->workerArgs);
    free(pool->threads);
    free(pool);
}

static void *lc_enqueue_task(b2TaskCallback *task, int itemCount, int minRange, void *taskContext, void *userContext) {
    LcTaskPool *pool = (LcTaskPool *)userContext;
    if (!pool || !task || itemCount <= 0) return NULL;
    if (minRange < 1) minRange = 1;

    int chunks = lc_task_chunk_count(itemCount, minRange);
    if (chunks <= 1) {
        task(0, itemCount, 0, taskContext);
        return NULL;
    }

    LcTaskGroup *group = (LcTaskGroup *)calloc(1, sizeof(LcTaskGroup));
    if (!group) {
        task(0, itemCount, 0, taskContext);
        return NULL;
    }
    group->task = task;
    group->taskContext = taskContext;
    group->itemCount = itemCount;
    group->minRange = minRange;
    group->remaining = chunks;
    group->queued = 1;
    group->pool = pool;

    pthread_mutex_lock(&pool->mutex);
    if (pool->tail) pool->tail->next = group; else pool->head = group;
    pool->tail = group;
    pthread_cond_broadcast(&pool->workCond);
    pthread_mutex_unlock(&pool->mutex);
    return group;
}

static void lc_finish_task(void *userTask, void *userContext) {
    LcTaskGroup *group = (LcTaskGroup *)userTask;
    LcTaskPool *pool = (LcTaskPool *)userContext;
    if (!group || !pool) return;

    for (;;) {
        pthread_mutex_lock(&pool->mutex);
        if (group->remaining <= 0) { pthread_mutex_unlock(&pool->mutex); break; }
        int start = 0, end = 0;
        int have = lc_task_take_locked(pool, group, &start, &end);
        if (!have) {
            while (group->remaining > 0) pthread_cond_wait(&pool->doneCond, &pool->mutex);
            pthread_mutex_unlock(&pool->mutex);
            break;
        }
        pthread_mutex_unlock(&pool->mutex);

        group->task(start, end, 0, group->taskContext);
        pthread_mutex_lock(&pool->mutex);
        lc_task_complete_locked(pool, group);
        pthread_mutex_unlock(&pool->mutex);
    }
    free(group);
}
#else
typedef struct LcTaskPool LcTaskPool;
static LcTaskPool *lc_task_pool_create(int workerCount) { (void)workerCount; return NULL; }
static void lc_task_pool_destroy(LcTaskPool *pool) { (void)pool; }
#endif

/* Per-world task pools, indexed by table SLOT (not by the encoded handle,
 * which carries generation bits in its high part). */
static LcTaskPool **s_worldPools = NULL;
static int s_worldPoolsCap = 0;

static int world_pool_set(int slot, LcTaskPool *pool) {
    if (slot < 0) return 0;
    if (slot >= s_worldPoolsCap) {
        int nc = s_worldPoolsCap ? s_worldPoolsCap : 64;
        while (nc <= slot) nc *= 2;
        LcTaskPool **p = (LcTaskPool **)realloc(s_worldPools, (size_t)nc * sizeof(LcTaskPool *));
        if (!p) return 0;
        memset(p + s_worldPoolsCap, 0, (size_t)(nc - s_worldPoolsCap) * sizeof(LcTaskPool *));
        s_worldPools = p;
        s_worldPoolsCap = nc;
    }
    s_worldPools[slot] = pool;
    return 1;
}

static LcTaskPool *world_pool_take(int slot) {
    if (slot < 0 || slot >= s_worldPoolsCap) return NULL;
    LcTaskPool *pool = s_worldPools[slot];
    s_worldPools[slot] = NULL;
    return pool;
}

/* Recover integer handles from Box2D userData (0 if the object has gone away). */
static int body_handle_of_shape(b2ShapeId s) {
    if (!b2Shape_IsValid(s)) return 0;
    b2BodyId b = b2Shape_GetBody(s);
    if (!b2Body_IsValid(b)) return 0;
    return ud2h(b2Body_GetUserData(b));
}
static int shape_handle_of_id(b2ShapeId s) {
    return b2Shape_IsValid(s) ? ud2h(b2Shape_GetUserData(s)) : 0;
}
static int joint_handle_of_id(b2JointId j) {
    return b2Joint_IsValid(j) ? ud2h(b2Joint_GetUserData(j)) : 0;
}
static void retire_shape_id(b2ShapeId s) {
    int h = shape_handle_of_id(s);
    if (h) shapes_free_handle(h);
}
static void retire_joint_id(b2JointId j) {
    int h = joint_handle_of_id(j);
    if (h) joints_free_handle(h);
}

/* ------------------------------------------------------------------ */
/* Library / world                                                     */
/* ------------------------------------------------------------------ */
LC_API int b2lc_abi_version(void) { return LC_ABI_VERSION; }

static int b2lc_world_create_internal(double gx, double gy, int enableSleep, int enableContinuous, int workerCount) {
    if (!finite2(gx, gy)) return 0;
    b2WorldDef wd = b2DefaultWorldDef();
    wd.gravity = v2(gx, gy);
    wd.enableSleep = enableSleep ? true : false;
    wd.enableContinuous = enableContinuous ? true : false;

    LcTaskPool *pool = lc_task_pool_create(workerCount);
#if !defined(_WIN32)
    if (pool) {
        wd.workerCount = pool->workerCount;
        wd.enqueueTask = lc_enqueue_task;
        wd.finishTask = lc_finish_task;
        wd.userTaskContext = pool;
    }
#endif

    b2WorldId id = b2CreateWorld(&wd);
    int h = worlds_add(id);
    if (!h && b2World_IsValid(id)) b2DestroyWorld(id);
    if (!h) { lc_task_pool_destroy(pool); return 0; }
    if (!world_pool_set(worlds_slot_of(h), pool)) {
        b2DestroyWorld(id);
        worlds_free_handle(h);
        lc_task_pool_destroy(pool);
        return 0;
    }
    return h;
}

LC_API int b2lc_world_create(double gx, double gy, int enableSleep, int enableContinuous) {
    return b2lc_world_create_internal(gx, gy, enableSleep, enableContinuous, 1);
}

LC_API int b2lc_world_create_threaded(double gx, double gy, int enableSleep, int enableContinuous, int workerCount) {
    return b2lc_world_create_internal(gx, gy, enableSleep, enableContinuous, workerCount);
}

LC_API int b2lc_world_thread_count(int w) {
    int slot = worlds_slot_of(w);
    if (slot < 0 || slot >= s_worldPoolsCap || !s_worldPools[slot]) return 1;
#if !defined(_WIN32)
    return s_worldPools[slot]->workerCount;
#else
    return 1;
#endif
}

LC_API void b2lc_world_destroy(int w) {
    LcTaskPool *pool = world_pool_take(worlds_slot_of(w));
    b2WorldId id = worlds_get(w);
    if (b2World_IsValid(id)) {
        b2DestroyWorld(id);
        retire_invalid_child_handles();
    }
    worlds_free_handle(w);
    lc_task_pool_destroy(pool);
}

LC_API void b2lc_world_set_gravity(int w, double gx, double gy) {
    b2WorldId id = worlds_get(w);
    if (b2World_IsValid(id) && finite2(gx, gy)) b2World_SetGravity(id, v2(gx, gy));
}

LC_API void b2lc_world_enable_sleeping(int w, int flag) {
    b2WorldId id = worlds_get(w);
    if (b2World_IsValid(id)) b2World_EnableSleeping(id, flag ? true : false);
}

LC_API void b2lc_world_enable_continuous(int w, int flag) {
    b2WorldId id = worlds_get(w);
    if (b2World_IsValid(id)) b2World_EnableContinuous(id, flag ? true : false);
}

/* dt in seconds, subStepCount is the Soft Step sub-step count (e.g. 4). */
LC_API void b2lc_world_step(int w, double dt, int subStepCount) {
    b2WorldId id = worlds_get(w);
    if (!b2World_IsValid(id) || !positive(dt)) return;
    if (subStepCount < 1) subStepCount = 1;
    if (subStepCount > 64) subStepCount = 64;
    b2World_Step(id, (float)dt, subStepCount);
}

/* ------------------------------------------------------------------ */
/* Bodies   (type: 0 = static, 1 = kinematic, 2 = dynamic)             */
/* ------------------------------------------------------------------ */
LC_API int b2lc_body_create(int w, int type, double x, double y, double angle,
                            int isBullet, int fixedRotation) {
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid) || !valid_body_type(type) || !finite3(x, y, angle)) return 0;
    b2BodyDef bd = b2DefaultBodyDef();
    bd.type = (b2BodyType)type;
    bd.position = v2(x, y);
    bd.rotation = rotOf(angle);
    bd.isBullet = isBullet ? true : false;
    bd.fixedRotation = fixedRotation ? true : false;
    b2BodyId id = b2CreateBody(wid, &bd);
    int h = bodies_add(id);
    if (!h) { b2DestroyBody(id); return 0; }
    b2Body_SetUserData(id, h2ud(h));   /* so queries can map id -> handle */
    return h;
}

static void retire_body_children(b2BodyId id) {
    int n = b2Body_GetShapeCount(id);
    if (n > 0) {
        b2ShapeId *buf = (b2ShapeId *)malloc((size_t)n * sizeof(b2ShapeId));
        if (buf) {
            int got = b2Body_GetShapes(id, buf, n);
            for (int i = 0; i < got; i++) retire_shape_id(buf[i]);
            free(buf);
        }
    }
    n = b2Body_GetJointCount(id);
    if (n > 0) {
        b2JointId *buf = (b2JointId *)malloc((size_t)n * sizeof(b2JointId));
        if (buf) {
            int got = b2Body_GetJoints(id, buf, n);
            for (int i = 0; i < got; i++) retire_joint_id(buf[i]);
            free(buf);
        }
    }
}

LC_API void b2lc_body_destroy(int b) {
    b2BodyId id = bodies_get(b);
    if (b2Body_IsValid(id)) {
        retire_body_children(id);
        b2DestroyBody(id);
        retire_invalid_child_handles();
    }
    bodies_free_handle(b);
}

/* transform read-back (scalar getters keep the FFI boundary simple) */
LC_API double b2lc_body_x(int b)     { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetPosition(id).x : 0.0; }
LC_API double b2lc_body_y(int b)     { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetPosition(id).y : 0.0; }
LC_API double b2lc_body_angle(int b) { b2BodyId id = bodies_get(b); if (!b2Body_IsValid(id)) return 0.0; return (double)b2Rot_GetAngle(b2Body_GetRotation(id)); }

LC_API double b2lc_body_vx(int b)    { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLinearVelocity(id).x : 0.0; }
LC_API double b2lc_body_vy(int b)    { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLinearVelocity(id).y : 0.0; }
LC_API double b2lc_body_omega(int b) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetAngularVelocity(id) : 0.0; }
LC_API double b2lc_body_mass(int b)  { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetMass(id) : 0.0; }
LC_API int    b2lc_body_is_awake(int b) { b2BodyId id = bodies_get(b); return (b2Body_IsValid(id) && b2Body_IsAwake(id)) ? 1 : 0; }

/* world centre of mass (handy as a render anchor for off-centre shapes) */
LC_API double b2lc_body_world_center_x(int b) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetWorldCenterOfMass(id).x : 0.0; }
LC_API double b2lc_body_world_center_y(int b) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetWorldCenterOfMass(id).y : 0.0; }

LC_API int    b2lc_body_type(int b)      { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (int)b2Body_GetType(id) : 0; }
LC_API int    b2lc_body_is_bullet(int b) { b2BodyId id = bodies_get(b); return (b2Body_IsValid(id) && b2Body_IsBullet(id)) ? 1 : 0; }
LC_API int    b2lc_body_is_enabled(int b){ b2BodyId id = bodies_get(b); return (b2Body_IsValid(id) && b2Body_IsEnabled(id)) ? 1 : 0; }

LC_API double b2lc_body_linear_damping(int b)  { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLinearDamping(id) : 0.0; }
LC_API double b2lc_body_angular_damping(int b) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetAngularDamping(id) : 0.0; }
LC_API double b2lc_body_gravity_scale(int b)   { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetGravityScale(id) : 0.0; }

LC_API void b2lc_body_set_transform(int b, double x, double y, double angle) {
    b2BodyId id = bodies_get(b);
    if (b2Body_IsValid(id) && finite3(x, y, angle)) b2Body_SetTransform(id, v2(x, y), rotOf(angle));
}
LC_API void b2lc_body_set_velocity(int b, double vx, double vy) {
    b2BodyId id = bodies_get(b);
    if (b2Body_IsValid(id) && finite2(vx, vy)) b2Body_SetLinearVelocity(id, v2(vx, vy));
}
LC_API void b2lc_body_set_angular_velocity(int b, double w) {
    b2BodyId id = bodies_get(b);
    if (b2Body_IsValid(id) && finite1(w)) b2Body_SetAngularVelocity(id, (float)w);
}
LC_API void b2lc_body_apply_force(int b, double fx, double fy, int wake) {
    b2BodyId id = bodies_get(b);
    if (b2Body_IsValid(id) && finite2(fx, fy)) b2Body_ApplyForceToCenter(id, v2(fx, fy), wake ? true : false);
}
LC_API void b2lc_body_apply_impulse(int b, double ix, double iy, int wake) {
    b2BodyId id = bodies_get(b);
    if (b2Body_IsValid(id) && finite2(ix, iy)) b2Body_ApplyLinearImpulseToCenter(id, v2(ix, iy), wake ? true : false);
}
LC_API void b2lc_body_apply_torque(int b, double t, int wake) {
    b2BodyId id = bodies_get(b);
    if (b2Body_IsValid(id) && finite1(t)) b2Body_ApplyTorque(id, (float)t, wake ? true : false);
}
LC_API void b2lc_body_apply_angular_impulse(int b, double imp, int wake) {
    b2BodyId id = bodies_get(b);
    if (b2Body_IsValid(id) && finite1(imp)) b2Body_ApplyAngularImpulse(id, (float)imp, wake ? true : false);
}
LC_API void b2lc_body_set_bullet(int b, int flag)         { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) b2Body_SetBullet(id, flag ? true : false); }
LC_API void b2lc_body_set_awake(int b, int flag)          { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) b2Body_SetAwake(id, flag ? true : false); }
LC_API void b2lc_body_set_fixed_rotation(int b, int flag) { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) b2Body_SetFixedRotation(id, flag ? true : false); }
LC_API void b2lc_body_set_type(int b, int type)           { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id) && valid_body_type(type)) b2Body_SetType(id, (b2BodyType)type); }
LC_API void b2lc_body_set_linear_damping(int b, double d) { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id) && d >= 0.0 && finite1(d)) b2Body_SetLinearDamping(id, (float)d); }
LC_API void b2lc_body_set_angular_damping(int b, double d){ b2BodyId id = bodies_get(b); if (b2Body_IsValid(id) && d >= 0.0 && finite1(d)) b2Body_SetAngularDamping(id, (float)d); }
LC_API void b2lc_body_set_gravity_scale(int b, double s)  { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id) && finite1(s)) b2Body_SetGravityScale(id, (float)s); }
LC_API void b2lc_body_set_sleep_threshold(int b, double v){ b2BodyId id = bodies_get(b); if (b2Body_IsValid(id) && v >= 0.0 && finite1(v)) b2Body_SetSleepThreshold(id, (float)v); }
LC_API void b2lc_body_enable(int b)                       { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) b2Body_Enable(id); }
LC_API void b2lc_body_disable(int b)                      { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) b2Body_Disable(id); }

/* ------------------------------------------------------------------ */
/* Shapes (attached to a body)                                         */
/* ------------------------------------------------------------------ */
/* Pending shape-def overrides: optional extras a script can set just before the
 * next shape creation (sensor flag, collision filter, per-event flags, material
 * id). They are applied by fill_shape_def() and then reset, so they are strictly
 * one-shot — exactly like the b2lc_poly_* vertex builder. Tri-state ints use -1
 * for "leave the default"; "have*" flags mark a value that was explicitly set. */
static struct {
    int sensor, enableContact, enableSensorEv, enableHitEv, enablePreSolve;
    int haveFilter; double catBits, maskBits; int groupIndex;
    int haveMaterialId, materialId;
} s_sd = { -1, -1, -1, -1, -1, 0, 0.0, 0.0, 0, 0, 0 };   /* tri-states start at "leave default" */

static void reset_shapedef(void) {
    s_sd.sensor = s_sd.enableContact = s_sd.enableSensorEv = -1;
    s_sd.enableHitEv = s_sd.enablePreSolve = -1;
    s_sd.haveFilter = 0; s_sd.haveMaterialId = 0;
}

static void fill_shape_def(b2ShapeDef *sd, double density, double friction, double restitution) {
    *sd = b2DefaultShapeDef();
    sd->density = (float)nonneg_or(density, 0.0);
    sd->material.friction = (float)nonneg_or(friction, 0.0);       /* moved into material in v3.1 */
    sd->material.restitution = (float)nonneg_or(restitution, 0.0);
    sd->enableContactEvents = true;                /* off by default in v3.1; on so
                                                      b2ContactsUpdate() works out of
                                                      the box for collision detection */
    /* apply any pending one-shot overrides, then clear them */
    if (s_sd.sensor         >= 0) sd->isSensor             = s_sd.sensor ? true : false;
    if (s_sd.enableContact  >= 0) sd->enableContactEvents  = s_sd.enableContact ? true : false;
    if (s_sd.enableSensorEv >= 0) sd->enableSensorEvents   = s_sd.enableSensorEv ? true : false;
    if (s_sd.enableHitEv    >= 0) sd->enableHitEvents      = s_sd.enableHitEv ? true : false;
    if (s_sd.enablePreSolve >= 0) sd->enablePreSolveEvents = s_sd.enablePreSolve ? true : false;
    if (s_sd.haveFilter) {
        sd->filter.categoryBits = (uint64_t)s_sd.catBits;
        sd->filter.maskBits     = (uint64_t)s_sd.maskBits;
        sd->filter.groupIndex   = s_sd.groupIndex;
    }
    if (s_sd.haveMaterialId) sd->material.userMaterialId = s_sd.materialId;
    reset_shapedef();
}

/* shape-def builder setters (one-shot; consumed by the next shape creation) */
LC_API void b2lc_shapedef_reset(void)                      { reset_shapedef(); }
LC_API void b2lc_shapedef_set_sensor(int f)                { s_sd.sensor = f ? 1 : 0; }
LC_API void b2lc_shapedef_set_enable_contact_events(int f) { s_sd.enableContact = f ? 1 : 0; }
LC_API void b2lc_shapedef_set_enable_sensor_events(int f)  { s_sd.enableSensorEv = f ? 1 : 0; }
LC_API void b2lc_shapedef_set_enable_hit_events(int f)     { s_sd.enableHitEv = f ? 1 : 0; }
LC_API void b2lc_shapedef_set_enable_presolve_events(int f){ s_sd.enablePreSolve = f ? 1 : 0; }
LC_API void b2lc_shapedef_set_filter(double cat, double mask, int group) {
    if (!filter_bits_ok(cat) || !filter_bits_ok(mask)) return;
    s_sd.haveFilter = 1; s_sd.catBits = cat; s_sd.maskBits = mask; s_sd.groupIndex = group;
}
LC_API void b2lc_shapedef_set_material_id(int id)          { s_sd.haveMaterialId = 1; s_sd.materialId = id; }

/* register a freshly created shape, stamping its handle into userData */
static int register_shape(b2ShapeId id) {
    if (!b2Shape_IsValid(id)) return 0;
    int h = shapes_add(id);
    if (!h) return 0;
    b2Shape_SetUserData(id, h2ud(h));
    return h;
}

LC_API int b2lc_shape_add_box(int b, double hw, double hh,
                              double density, double friction, double restitution) {
    b2BodyId body = bodies_get(b);
    if (!b2Body_IsValid(body) || !positive(hw) || !positive(hh)) return 0;
    b2ShapeDef sd; fill_shape_def(&sd, density, friction, restitution);
    b2Polygon box = b2MakeBox((float)hw, (float)hh);
    b2ShapeId id = b2CreatePolygonShape(body, &sd, &box);
    int h = register_shape(id);
    if (!h && b2Shape_IsValid(id)) b2DestroyShape(id, true);
    return h;
}

LC_API int b2lc_shape_add_circle(int b, double cx, double cy, double radius,
                                 double density, double friction, double restitution) {
    b2BodyId body = bodies_get(b);
    if (!b2Body_IsValid(body) || !finite2(cx, cy) || !positive(radius)) return 0;
    b2ShapeDef sd; fill_shape_def(&sd, density, friction, restitution);
    b2Circle c; c.center = v2(cx, cy); c.radius = (float)radius;
    b2ShapeId id = b2CreateCircleShape(body, &sd, &c);
    int h = register_shape(id);
    if (!h && b2Shape_IsValid(id)) b2DestroyShape(id, true);
    return h;
}

/* Capsule: a rounded line from (x1,y1) to (x2,y2) with the given radius. */
LC_API int b2lc_shape_add_capsule(int b, double x1, double y1, double x2, double y2,
                                  double radius, double density, double friction, double restitution) {
    b2BodyId body = bodies_get(b);
    if (!b2Body_IsValid(body) || !finite2(x1, y1) || !finite2(x2, y2) || !positive(radius)) return 0;
    if (x1 == x2 && y1 == y2) return 0;   /* degenerate capsule: use a circle instead */
    b2ShapeDef sd; fill_shape_def(&sd, density, friction, restitution);
    b2Capsule cap; cap.center1 = v2(x1, y1); cap.center2 = v2(x2, y2); cap.radius = (float)radius;
    b2ShapeId id = b2CreateCapsuleShape(body, &sd, &cap);
    int h = register_shape(id);
    if (!h && b2Shape_IsValid(id)) b2DestroyShape(id, true);
    return h;
}

/* Segment: a one-sided line edge, best used on static bodies for ground. */
LC_API int b2lc_shape_add_segment(int b, double x1, double y1, double x2, double y2,
                                  double friction, double restitution) {
    b2BodyId body = bodies_get(b);
    if (!b2Body_IsValid(body) || !finite2(x1, y1) || !finite2(x2, y2) || (x1 == x2 && y1 == y2)) return 0;
    b2ShapeDef sd; fill_shape_def(&sd, 0.0, friction, restitution);  /* segments are massless */
    b2Segment seg; seg.point1 = v2(x1, y1); seg.point2 = v2(x2, y2);
    b2ShapeId id = b2CreateSegmentShape(body, &sd, &seg);
    int h = register_shape(id);
    if (!h && b2Shape_IsValid(id)) b2DestroyShape(id, true);
    return h;
}

/* Convex polygon builder: accumulate local points, then create.        */
/* Avoids passing arrays across the FFI boundary. Max 8 vertices.        */
#define LC_MAX_POLY 8
static b2Vec2 s_poly[LC_MAX_POLY];
static int    s_polyCnt = 0;

LC_API void b2lc_poly_begin(void) { s_polyCnt = 0; }
LC_API void b2lc_poly_add(double x, double y) {
    if (s_polyCnt < LC_MAX_POLY && finite2(x, y)) s_poly[s_polyCnt++] = v2(x, y);
}
LC_API int b2lc_shape_add_polygon(int b, double density, double friction, double restitution) {
    b2BodyId body = bodies_get(b);
    if (!b2Body_IsValid(body)) return 0;
    if (s_polyCnt < 3) return 0;
    b2Hull hull = b2ComputeHull(s_poly, s_polyCnt);
    if (hull.count < 3) return 0;
    b2Polygon poly = b2MakePolygon(&hull, 0.0f);
    b2ShapeDef sd; fill_shape_def(&sd, density, friction, restitution);
    b2ShapeId id = b2CreatePolygonShape(body, &sd, &poly);
    int h = register_shape(id);
    if (!h && b2Shape_IsValid(id)) b2DestroyShape(id, true);
    return h;
}

LC_API void b2lc_shape_destroy(int s) {
    b2ShapeId id = shapes_get(s);
    if (b2Shape_IsValid(id)) b2DestroyShape(id, true);
    shapes_free_handle(s);
}

/* runtime material edits + queries */
LC_API void b2lc_shape_set_friction(int s, double f)    { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id) && f >= 0.0 && finite1(f)) b2Shape_SetFriction(id, (float)f); }
LC_API void b2lc_shape_set_restitution(int s, double r) { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id) && r >= 0.0 && finite1(r)) b2Shape_SetRestitution(id, (float)r); }
LC_API void b2lc_shape_set_density(int s, double d)     { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id) && d >= 0.0 && finite1(d)) b2Shape_SetDensity(id, (float)d, true); }
LC_API int  b2lc_shape_body(int s)                      { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? ud2h(b2Body_GetUserData(b2Shape_GetBody(id))) : 0; }
LC_API int  b2lc_shape_test_point(int s, double x, double y) { b2ShapeId id = shapes_get(s); return (b2Shape_IsValid(id) && b2Shape_TestPoint(id, v2(x, y))) ? 1 : 0; }

/* ------------------------------------------------------------------ */
/* Joints                                                              */
/* ------------------------------------------------------------------ */
/* register a freshly created joint, stamping its handle into userData so the
 * generic getters (GetBodyA/B), body->joint enumeration and round-trips work. */
static int register_joint(b2JointId id) {
    if (!b2Joint_IsValid(id)) return 0;
    int h = joints_add(id);
    if (!h) { b2DestroyJoint(id); return 0; }
    b2Joint_SetUserData(id, h2ud(h));
    return h;
}
static int joint_handle_of(b2JointId j) {
    return joint_handle_of_id(j);
}

LC_API int b2lc_joint_revolute(int w, int bA, int bB,
                               double ax, double ay, double bx, double by, int collide) {
    b2WorldId wid = worlds_get(w);
    b2BodyId a = bodies_get(bA), b = bodies_get(bB);
    if (!b2World_IsValid(wid) || !b2Body_IsValid(a) || !b2Body_IsValid(b)) return 0;
    if (!finite2(ax, ay) || !finite2(bx, by)) return 0;
    b2RevoluteJointDef jd = b2DefaultRevoluteJointDef();
    jd.bodyIdA = a;
    jd.bodyIdB = b;
    jd.localAnchorA = v2(ax, ay);
    jd.localAnchorB = v2(bx, by);
    jd.collideConnected = collide ? true : false;
    return register_joint(b2CreateRevoluteJoint(wid, &jd));
}
LC_API void b2lc_revolute_enable_limit(int j, int enable, double lowerRad, double upperRad) {
    b2JointId jj = joints_get(j);
    if (!b2Joint_IsValid(jj) || !finite2(lowerRad, upperRad) || lowerRad > upperRad) return;
    /* Box2D requires revolute limits inside +/-0.95*pi; clamp like the engine
     * expects instead of letting an out-of-range request trip its asserts. */
    const double maxAng = 0.95 * 3.14159265358979323846;
    if (lowerRad < -maxAng) lowerRad = -maxAng;
    if (upperRad >  maxAng) upperRad =  maxAng;
    if (lowerRad > upperRad) lowerRad = upperRad;
    b2RevoluteJoint_EnableLimit(jj, enable ? true : false);
    b2RevoluteJoint_SetLimits(jj, (float)lowerRad, (float)upperRad);
}
LC_API void b2lc_revolute_enable_motor(int j, int enable, double speed, double maxTorque) {
    b2JointId jj = joints_get(j);
    if (!b2Joint_IsValid(jj) || !finite2(speed, maxTorque)) return;
    b2RevoluteJoint_EnableMotor(jj, enable ? true : false);
    b2RevoluteJoint_SetMotorSpeed(jj, (float)speed);
    b2RevoluteJoint_SetMaxMotorTorque(jj, (float)maxTorque);
}
LC_API double b2lc_revolute_angle(int j) { b2JointId jj = joints_get(j); return b2Joint_IsValid(jj) ? (double)b2RevoluteJoint_GetAngle(jj) : 0.0; }

LC_API int b2lc_joint_distance(int w, int bA, int bB,
                               double ax, double ay, double bx, double by,
                               double length, int collide) {
    b2WorldId wid = worlds_get(w);
    b2BodyId a = bodies_get(bA), b = bodies_get(bB);
    if (!b2World_IsValid(wid) || !b2Body_IsValid(a) || !b2Body_IsValid(b)) return 0;
    if (!finite2(ax, ay) || !finite2(bx, by) || !finite1(length)) return 0;
    /* Box2D requires length > 0 (its own SetLength clamps to linear slop). */
    if (length < 0.005) length = 0.005;
    b2DistanceJointDef jd = b2DefaultDistanceJointDef();
    jd.bodyIdA = a;
    jd.bodyIdB = b;
    jd.localAnchorA = v2(ax, ay);
    jd.localAnchorB = v2(bx, by);
    jd.length = (float)length;
    jd.collideConnected = collide ? true : false;
    return register_joint(b2CreateDistanceJoint(wid, &jd));
}
LC_API void b2lc_distance_set_length(int j, double length) {
    b2JointId jj = joints_get(j);
    if (b2Joint_IsValid(jj) && finite1(length)) b2DistanceJoint_SetLength(jj, (float)length);
}
LC_API void b2lc_distance_set_length_range(int j, double minLen, double maxLen) {
    b2JointId jj = joints_get(j);
    if (!b2Joint_IsValid(jj) || !finite2(minLen, maxLen) || minLen > maxLen) return;
    b2DistanceJoint_EnableLimit(jj, true);
    b2DistanceJoint_SetLengthRange(jj, (float)minLen, (float)maxLen);
}
LC_API void b2lc_distance_enable_spring(int j, int enable, double hertz, double dampingRatio) {
    b2JointId jj = joints_get(j);
    if (!b2Joint_IsValid(jj) || !finite2(hertz, dampingRatio)) return;
    b2DistanceJoint_EnableSpring(jj, enable ? true : false);
    b2DistanceJoint_SetSpringHertz(jj, (float)hertz);
    b2DistanceJoint_SetSpringDampingRatio(jj, (float)dampingRatio);
}
LC_API double b2lc_distance_length(int j) { b2JointId jj = joints_get(j); return b2Joint_IsValid(jj) ? (double)b2DistanceJoint_GetLength(jj) : 0.0; }

/* Weld: rigidly glue two bodies. hertz 0 (the default) = perfectly rigid. */
LC_API int b2lc_joint_weld(int w, int bA, int bB,
                           double ax, double ay, double bx, double by,
                           double refAngle, int collide) {
    b2WorldId wid = worlds_get(w);
    b2BodyId a = bodies_get(bA), b = bodies_get(bB);
    if (!b2World_IsValid(wid) || !b2Body_IsValid(a) || !b2Body_IsValid(b)) return 0;
    if (!finite2(ax, ay) || !finite2(bx, by) || !finite1(refAngle)) return 0;
    b2WeldJointDef jd = b2DefaultWeldJointDef();
    jd.bodyIdA = a;
    jd.bodyIdB = b;
    jd.localAnchorA = v2(ax, ay);
    jd.localAnchorB = v2(bx, by);
    jd.referenceAngle = (float)refAngle;
    jd.collideConnected = collide ? true : false;
    return register_joint(b2CreateWeldJoint(wid, &jd));
}
LC_API void b2lc_weld_set_stiffness(int j, double linHertz, double linDamping, double angHertz, double angDamping) {
    b2JointId jj = joints_get(j);
    if (!b2Joint_IsValid(jj) || !finite2(linHertz, linDamping) || !finite2(angHertz, angDamping)) return;
    b2WeldJoint_SetLinearHertz(jj, (float)linHertz);
    b2WeldJoint_SetLinearDampingRatio(jj, (float)linDamping);
    b2WeldJoint_SetAngularHertz(jj, (float)angHertz);
    b2WeldJoint_SetAngularDampingRatio(jj, (float)angDamping);
}

/* Prismatic: constrain bodyB to slide along an axis (in bodyA's frame). */
LC_API int b2lc_joint_prismatic(int w, int bA, int bB,
                                double ax, double ay, double bx, double by,
                                double axisX, double axisY, double refAngle, int collide) {
    b2WorldId wid = worlds_get(w);
    b2BodyId a = bodies_get(bA), b = bodies_get(bB);
    if (!b2World_IsValid(wid) || !b2Body_IsValid(a) || !b2Body_IsValid(b)) return 0;
    if (!finite2(ax, ay) || !finite2(bx, by) || !finite1(refAngle)) return 0;
    if (!finite2(axisX, axisY) || (axisX == 0.0 && axisY == 0.0)) return 0;  /* axis must normalize */
    b2PrismaticJointDef jd = b2DefaultPrismaticJointDef();
    jd.bodyIdA = a;
    jd.bodyIdB = b;
    jd.localAnchorA = v2(ax, ay);
    jd.localAnchorB = v2(bx, by);
    jd.localAxisA = b2Normalize(v2(axisX, axisY));
    jd.referenceAngle = (float)refAngle;
    jd.collideConnected = collide ? true : false;
    return register_joint(b2CreatePrismaticJoint(wid, &jd));
}
LC_API void b2lc_prismatic_enable_limit(int j, int enable, double lower, double upper) {
    b2JointId jj = joints_get(j);
    if (!b2Joint_IsValid(jj) || !finite2(lower, upper) || lower > upper) return;
    b2PrismaticJoint_EnableLimit(jj, enable ? true : false);
    b2PrismaticJoint_SetLimits(jj, (float)lower, (float)upper);
}
LC_API void b2lc_prismatic_enable_motor(int j, int enable, double speed, double maxForce) {
    b2JointId jj = joints_get(j);
    if (!b2Joint_IsValid(jj) || !finite2(speed, maxForce)) return;
    b2PrismaticJoint_EnableMotor(jj, enable ? true : false);
    b2PrismaticJoint_SetMotorSpeed(jj, (float)speed);
    b2PrismaticJoint_SetMaxMotorForce(jj, (float)maxForce);
}
LC_API double b2lc_prismatic_translation(int j) { b2JointId jj = joints_get(j); return b2Joint_IsValid(jj) ? (double)b2PrismaticJoint_GetTranslation(jj) : 0.0; }

/* Wheel: a sprung sliding axis plus free rotation - for vehicle wheels. */
LC_API int b2lc_joint_wheel(int w, int bA, int bB,
                            double ax, double ay, double bx, double by,
                            double axisX, double axisY, int collide) {
    b2WorldId wid = worlds_get(w);
    b2BodyId a = bodies_get(bA), b = bodies_get(bB);
    if (!b2World_IsValid(wid) || !b2Body_IsValid(a) || !b2Body_IsValid(b)) return 0;
    if (!finite2(ax, ay) || !finite2(bx, by)) return 0;
    if (!finite2(axisX, axisY) || (axisX == 0.0 && axisY == 0.0)) return 0;  /* axis must normalize */
    b2WheelJointDef jd = b2DefaultWheelJointDef();
    jd.bodyIdA = a;
    jd.bodyIdB = b;
    jd.localAnchorA = v2(ax, ay);
    jd.localAnchorB = v2(bx, by);
    jd.localAxisA = b2Normalize(v2(axisX, axisY));
    jd.collideConnected = collide ? true : false;
    return register_joint(b2CreateWheelJoint(wid, &jd));
}
LC_API void b2lc_wheel_enable_spring(int j, int enable, double hertz, double dampingRatio) {
    b2JointId jj = joints_get(j);
    if (!b2Joint_IsValid(jj) || !finite2(hertz, dampingRatio)) return;
    b2WheelJoint_EnableSpring(jj, enable ? true : false);
    b2WheelJoint_SetSpringHertz(jj, (float)hertz);
    b2WheelJoint_SetSpringDampingRatio(jj, (float)dampingRatio);
}
LC_API void b2lc_wheel_enable_motor(int j, int enable, double speed, double maxTorque) {
    b2JointId jj = joints_get(j);
    if (!b2Joint_IsValid(jj) || !finite2(speed, maxTorque)) return;
    b2WheelJoint_EnableMotor(jj, enable ? true : false);
    b2WheelJoint_SetMotorSpeed(jj, (float)speed);
    b2WheelJoint_SetMaxMotorTorque(jj, (float)maxTorque);
}

/* Mouse (target) joint: drag bodyB toward a moving world-space target.
 * bodyA is only used as a reference frame - pass any static body. */
LC_API int b2lc_joint_mouse(int w, int bA, int bB,
                            double tx, double ty, double hertz, double dampingRatio, double maxForce) {
    b2WorldId wid = worlds_get(w);
    b2BodyId a = bodies_get(bA), b = bodies_get(bB);
    if (!b2World_IsValid(wid) || !b2Body_IsValid(a) || !b2Body_IsValid(b)) return 0;
    if (!finite2(tx, ty) || !finite3(hertz, dampingRatio, maxForce)) return 0;
    b2MouseJointDef jd = b2DefaultMouseJointDef();
    jd.bodyIdA = a;
    jd.bodyIdB = b;
    jd.target = v2(tx, ty);
    jd.hertz = (float)hertz;
    jd.dampingRatio = (float)dampingRatio;
    jd.maxForce = (float)maxForce;
    return register_joint(b2CreateMouseJoint(wid, &jd));
}
LC_API void b2lc_mouse_set_target(int j, double tx, double ty) {
    b2JointId jj = joints_get(j);
    if (b2Joint_IsValid(jj) && finite2(tx, ty)) b2MouseJoint_SetTarget(jj, v2(tx, ty));
}

LC_API void b2lc_joint_destroy(int j) {
    b2JointId id = joints_get(j);
    if (b2Joint_IsValid(id)) b2DestroyJoint(id);
    joints_free_handle(j);
}

/* ------------------------------------------------------------------ */
/* World queries: ray cast + point pick                                */
/* Results are stashed in static state and read back with getters,     */
/* mirroring the polygon-builder pattern (no struct marshalling).      */
/* ------------------------------------------------------------------ */
static int    s_ray_hit = 0, s_ray_body = 0, s_ray_shape = 0;
static double s_ray_px = 0, s_ray_py = 0, s_ray_nx = 0, s_ray_ny = 0, s_ray_frac = 0;

LC_API int b2lc_cast_ray_closest(int w, double x1, double y1, double x2, double y2) {
    s_ray_hit = s_ray_body = s_ray_shape = 0;
    s_ray_px = s_ray_py = s_ray_nx = s_ray_ny = s_ray_frac = 0;
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid)) return 0;
    b2RayResult r = b2World_CastRayClosest(wid, v2(x1, y1), v2(x2 - x1, y2 - y1), b2DefaultQueryFilter());
    if (r.hit) {
        s_ray_hit  = 1;
        s_ray_px   = r.point.x;  s_ray_py = r.point.y;
        s_ray_nx   = r.normal.x; s_ray_ny = r.normal.y;
        s_ray_frac = r.fraction;
        s_ray_shape = b2Shape_IsValid(r.shapeId) ? ud2h(b2Shape_GetUserData(r.shapeId)) : 0;
        s_ray_body  = body_handle_of_shape(r.shapeId);
    }
    return s_ray_hit;
}
LC_API int    b2lc_ray_body(void)     { return s_ray_body; }
LC_API int    b2lc_ray_shape(void)    { return s_ray_shape; }
LC_API double b2lc_ray_x(void)        { return s_ray_px; }
LC_API double b2lc_ray_y(void)        { return s_ray_py; }
LC_API double b2lc_ray_normal_x(void) { return s_ray_nx; }
LC_API double b2lc_ray_normal_y(void) { return s_ray_ny; }
LC_API double b2lc_ray_fraction(void) { return s_ray_frac; }

/* Point pick: return the handle of the first body whose shape covers (x,y). */
static b2Vec2 s_pick_pt;
static int    s_pick_body;
static bool pick_cb(b2ShapeId shapeId, void *ctx) {
    (void)ctx;
    if (b2Shape_TestPoint(shapeId, s_pick_pt)) {
        s_pick_body = body_handle_of_shape(shapeId);
        return false;   /* found one; stop the query */
    }
    return true;        /* keep searching */
}
LC_API int b2lc_body_at_point(int w, double x, double y) {
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid)) return 0;
    s_pick_pt = v2(x, y);
    s_pick_body = 0;
    const float e = 0.001f;
    b2AABB aabb;
    aabb.lowerBound = v2(x - e, y - e);
    aabb.upperBound = v2(x + e, y + e);
    b2World_OverlapAABB(wid, aabb, b2DefaultQueryFilter(), pick_cb, NULL);
    return s_pick_body;
}

/* ------------------------------------------------------------------ */
/* Contact events. Call b2lc_contacts_update(world) once per step      */
/* (after b2Step), then read the snapshotted begin/end touch pairs.    */
/* Each event yields the two body handles that started/stopped touching.*/
/* ------------------------------------------------------------------ */
static int *s_begin = NULL; static int s_beginCap = 0, s_beginCnt = 0;
static int *s_end   = NULL; static int s_endCap   = 0, s_endCnt   = 0;

/* hit events (enableHitEvents): impact point/normal/approach-speed per pair */
typedef struct { int a, b; double px, py, nx, ny, speed; } LcHit;
static LcHit *s_hit = NULL; static int s_hitCap = 0, s_hitCnt = 0;

static int *ensure_cap(int *arr, int *cap, int needPairs) {
    int need = needPairs * 2;
    if (need > *cap) {
        int *p = (int *)realloc(arr, (size_t)need * sizeof(int));
        if (!p) return NULL;
        arr = p;
        *cap = need;
    }
    return arr;
}

LC_API int b2lc_contacts_update(int w) {
    s_beginCnt = s_endCnt = s_hitCnt = 0;
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid)) return 0;
    b2ContactEvents ev = b2World_GetContactEvents(wid);

    int *begin = ensure_cap(s_begin, &s_beginCap, ev.beginCount);
    if (ev.beginCount > 0 && !begin) return 0;
    s_begin = begin;
    for (int i = 0; i < ev.beginCount; i++) {
        s_begin[2 * i]     = body_handle_of_shape(ev.beginEvents[i].shapeIdA);
        s_begin[2 * i + 1] = body_handle_of_shape(ev.beginEvents[i].shapeIdB);
    }
    s_beginCnt = ev.beginCount;

    int *end = ensure_cap(s_end, &s_endCap, ev.endCount);
    if (ev.endCount > 0 && !end) { s_beginCnt = 0; return 0; }
    s_end = end;
    for (int i = 0; i < ev.endCount; i++) {
        s_end[2 * i]     = body_handle_of_shape(ev.endEvents[i].shapeIdA);
        s_end[2 * i + 1] = body_handle_of_shape(ev.endEvents[i].shapeIdB);
    }
    s_endCnt = ev.endCount;

    if (!grow_buffer((void **)&s_hit, &s_hitCap, ev.hitCount, sizeof(LcHit))) {
        s_beginCnt = s_endCnt = 0;
        return 0;
    }
    for (int i = 0; i < ev.hitCount; i++) {
        s_hit[i].a  = body_handle_of_shape(ev.hitEvents[i].shapeIdA);
        s_hit[i].b  = body_handle_of_shape(ev.hitEvents[i].shapeIdB);
        s_hit[i].px = ev.hitEvents[i].point.x;  s_hit[i].py = ev.hitEvents[i].point.y;
        s_hit[i].nx = ev.hitEvents[i].normal.x; s_hit[i].ny = ev.hitEvents[i].normal.y;
        s_hit[i].speed = ev.hitEvents[i].approachSpeed;
    }
    s_hitCnt = ev.hitCount;

    return s_beginCnt;
}
LC_API int b2lc_contact_begin_count(void)   { return s_beginCnt; }
LC_API int b2lc_contact_end_count(void)     { return s_endCnt; }
LC_API int b2lc_contact_begin_a(int i) { return (i >= 0 && i < s_beginCnt) ? s_begin[2 * i]     : 0; }
LC_API int b2lc_contact_begin_b(int i) { return (i >= 0 && i < s_beginCnt) ? s_begin[2 * i + 1] : 0; }
LC_API int b2lc_contact_end_a(int i)   { return (i >= 0 && i < s_endCnt)   ? s_end[2 * i]       : 0; }
LC_API int b2lc_contact_end_b(int i)   { return (i >= 0 && i < s_endCnt)   ? s_end[2 * i + 1]   : 0; }

/* ================================================================== */
/* ABI v3 additions: the full Box2D v3.1.0 live-object surface.        */
/* Everything below reuses the patterns above (scalar getters, the     */
/* poly/chain input builders, the ray/contact output stashes, growable */
/* snapshots, handle tables). No new FFI machinery.                    */
/* ================================================================== */

/* id -> integer-handle helpers (mirror body_handle_of_shape for bodies/shapes) */
static int body_h(b2BodyId b)   { return b2Body_IsValid(b)  ? ud2h(b2Body_GetUserData(b))  : 0; }
static int shape_h(b2ShapeId s) { return shape_handle_of_id(s); }

/* ---- contact HIT events (snapshotted by b2lc_contacts_update) ------ */
LC_API int    b2lc_contact_hit_count(void)  { return s_hitCnt; }
LC_API int    b2lc_contact_hit_a(int i)     { return (i >= 0 && i < s_hitCnt) ? s_hit[i].a : 0; }
LC_API int    b2lc_contact_hit_b(int i)     { return (i >= 0 && i < s_hitCnt) ? s_hit[i].b : 0; }
LC_API double b2lc_contact_hit_x(int i)     { return (i >= 0 && i < s_hitCnt) ? s_hit[i].px : 0.0; }
LC_API double b2lc_contact_hit_y(int i)     { return (i >= 0 && i < s_hitCnt) ? s_hit[i].py : 0.0; }
LC_API double b2lc_contact_hit_nx(int i)    { return (i >= 0 && i < s_hitCnt) ? s_hit[i].nx : 0.0; }
LC_API double b2lc_contact_hit_ny(int i)    { return (i >= 0 && i < s_hitCnt) ? s_hit[i].ny : 0.0; }
LC_API double b2lc_contact_hit_speed(int i) { return (i >= 0 && i < s_hitCnt) ? s_hit[i].speed : 0.0; }

/* ---- sensor events ------------------------------------------------- */
/* begin/end touch pairs are (sensorShape, visitorShape) — sensors are a
 * shape-level concept, so these expose SHAPE handles (not bodies). */
static int *s_senB = NULL; static int s_senBCap = 0, s_senBCnt = 0;
static int *s_senE = NULL; static int s_senECap = 0, s_senECnt = 0;

LC_API int b2lc_sensors_update(int w) {
    s_senBCnt = s_senECnt = 0;
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid)) return 0;
    b2SensorEvents ev = b2World_GetSensorEvents(wid);
    int *senB = ensure_cap(s_senB, &s_senBCap, ev.beginCount);
    if (ev.beginCount > 0 && !senB) return 0;
    s_senB = senB;
    for (int i = 0; i < ev.beginCount; i++) {
        s_senB[2 * i]     = shape_h(ev.beginEvents[i].sensorShapeId);
        s_senB[2 * i + 1] = shape_h(ev.beginEvents[i].visitorShapeId);
    }
    s_senBCnt = ev.beginCount;
    int *senE = ensure_cap(s_senE, &s_senECap, ev.endCount);
    if (ev.endCount > 0 && !senE) { s_senBCnt = 0; return 0; }
    s_senE = senE;
    for (int i = 0; i < ev.endCount; i++) {
        s_senE[2 * i]     = shape_h(ev.endEvents[i].sensorShapeId);   /* may be destroyed -> 0 */
        s_senE[2 * i + 1] = shape_h(ev.endEvents[i].visitorShapeId);
    }
    s_senECnt = ev.endCount;
    return s_senBCnt;
}
LC_API int b2lc_sensor_begin_count(void)      { return s_senBCnt; }
LC_API int b2lc_sensor_end_count(void)        { return s_senECnt; }
LC_API int b2lc_sensor_begin_sensor(int i)    { return (i >= 0 && i < s_senBCnt) ? s_senB[2 * i]     : 0; }
LC_API int b2lc_sensor_begin_visitor(int i)   { return (i >= 0 && i < s_senBCnt) ? s_senB[2 * i + 1] : 0; }
LC_API int b2lc_sensor_end_sensor(int i)      { return (i >= 0 && i < s_senECnt) ? s_senE[2 * i]     : 0; }
LC_API int b2lc_sensor_end_visitor(int i)     { return (i >= 0 && i < s_senECnt) ? s_senE[2 * i + 1] : 0; }

/* ---- body MOVE events (efficient bulk transform readback) ---------- */
typedef struct { int body; double x, y, angle; int asleep; } LcMove;
static LcMove *s_move = NULL; static int s_moveCap = 0, s_moveCnt = 0;

LC_API int b2lc_bodies_update(int w) {
    s_moveCnt = 0;
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid)) return 0;
    b2BodyEvents ev = b2World_GetBodyEvents(wid);
    if (!grow_buffer((void **)&s_move, &s_moveCap, ev.moveCount, sizeof(LcMove))) return 0;
    for (int i = 0; i < ev.moveCount; i++) {
        b2Transform t = ev.moveEvents[i].transform;
        s_move[i].body   = ud2h(ev.moveEvents[i].userData);   /* the stored handle */
        s_move[i].x      = t.p.x;
        s_move[i].y      = t.p.y;
        s_move[i].angle  = b2Rot_GetAngle(t.q);
        s_move[i].asleep = ev.moveEvents[i].fellAsleep ? 1 : 0;
    }
    s_moveCnt = ev.moveCount;
    return s_moveCnt;
}
LC_API int    b2lc_body_move_count(void)    { return s_moveCnt; }
LC_API int    b2lc_body_move_body(int i)    { return (i >= 0 && i < s_moveCnt) ? s_move[i].body   : 0; }
LC_API double b2lc_body_move_x(int i)       { return (i >= 0 && i < s_moveCnt) ? s_move[i].x      : 0.0; }
LC_API double b2lc_body_move_y(int i)       { return (i >= 0 && i < s_moveCnt) ? s_move[i].y      : 0.0; }
LC_API double b2lc_body_move_angle(int i)   { return (i >= 0 && i < s_moveCnt) ? s_move[i].angle  : 0.0; }
LC_API int    b2lc_body_move_asleep(int i)  { return (i >= 0 && i < s_moveCnt) ? s_move[i].asleep : 0; }

/* ------------------------------------------------------------------ */
/* World tuning + info + native explode + profile/counters             */
/* ------------------------------------------------------------------ */
LC_API double b2lc_world_gravity_x(int w) { b2WorldId id = worlds_get(w); return b2World_IsValid(id) ? (double)b2World_GetGravity(id).x : 0.0; }
LC_API double b2lc_world_gravity_y(int w) { b2WorldId id = worlds_get(w); return b2World_IsValid(id) ? (double)b2World_GetGravity(id).y : 0.0; }
LC_API void   b2lc_world_set_restitution_threshold(int w, double v) { b2WorldId id = worlds_get(w); if (b2World_IsValid(id) && finite1(v) && v >= 0.0) b2World_SetRestitutionThreshold(id, (float)v); }
LC_API double b2lc_world_restitution_threshold(int w) { b2WorldId id = worlds_get(w); return b2World_IsValid(id) ? (double)b2World_GetRestitutionThreshold(id) : 0.0; }
LC_API void   b2lc_world_set_hit_event_threshold(int w, double v) { b2WorldId id = worlds_get(w); if (b2World_IsValid(id) && finite1(v) && v >= 0.0) b2World_SetHitEventThreshold(id, (float)v); }
LC_API double b2lc_world_hit_event_threshold(int w) { b2WorldId id = worlds_get(w); return b2World_IsValid(id) ? (double)b2World_GetHitEventThreshold(id) : 0.0; }
LC_API void   b2lc_world_set_contact_tuning(int w, double hertz, double damping, double pushSpeed) { b2WorldId id = worlds_get(w); if (b2World_IsValid(id) && finite3(hertz, damping, pushSpeed) && hertz >= 0.0 && damping >= 0.0 && pushSpeed >= 0.0) b2World_SetContactTuning(id, (float)hertz, (float)damping, (float)pushSpeed); }
LC_API void   b2lc_world_set_joint_tuning(int w, double hertz, double damping) { b2WorldId id = worlds_get(w); if (b2World_IsValid(id) && finite2(hertz, damping) && hertz >= 0.0 && damping >= 0.0) b2World_SetJointTuning(id, (float)hertz, (float)damping); }
LC_API void   b2lc_world_set_maximum_linear_speed(int w, double v) { b2WorldId id = worlds_get(w); if (b2World_IsValid(id) && positive(v)) b2World_SetMaximumLinearSpeed(id, (float)v); }
LC_API double b2lc_world_maximum_linear_speed(int w) { b2WorldId id = worlds_get(w); return b2World_IsValid(id) ? (double)b2World_GetMaximumLinearSpeed(id) : 0.0; }
LC_API void   b2lc_world_enable_warm_starting(int w, int f) { b2WorldId id = worlds_get(w); if (b2World_IsValid(id)) b2World_EnableWarmStarting(id, f ? true : false); }
LC_API int    b2lc_world_is_warm_starting(int w) { b2WorldId id = worlds_get(w); return (b2World_IsValid(id) && b2World_IsWarmStartingEnabled(id)) ? 1 : 0; }
LC_API void   b2lc_world_enable_speculative(int w, int f) { b2WorldId id = worlds_get(w); if (b2World_IsValid(id)) b2World_EnableSpeculative(id, f ? true : false); }
LC_API int    b2lc_world_is_sleeping_enabled(int w) { b2WorldId id = worlds_get(w); return (b2World_IsValid(id) && b2World_IsSleepingEnabled(id)) ? 1 : 0; }
LC_API int    b2lc_world_is_continuous_enabled(int w) { b2WorldId id = worlds_get(w); return (b2World_IsValid(id) && b2World_IsContinuousEnabled(id)) ? 1 : 0; }
LC_API int    b2lc_world_awake_body_count(int w) { b2WorldId id = worlds_get(w); return b2World_IsValid(id) ? b2World_GetAwakeBodyCount(id) : 0; }

LC_API void b2lc_world_explode(int w, double x, double y, double radius, double falloff, double impulsePerLength) {
    b2WorldId id = worlds_get(w);
    if (!b2World_IsValid(id) || !finite2(x, y) || !finite3(radius, falloff, impulsePerLength)) return;
    if (radius < 0.0 || falloff < 0.0) return;
    b2ExplosionDef ed = b2DefaultExplosionDef();
    ed.position = v2(x, y);
    ed.radius = (float)radius;
    ed.falloff = (float)falloff;
    ed.impulsePerLength = (float)impulsePerLength;
    b2World_Explode(id, &ed);
}

static b2Profile s_profile;
LC_API void   b2lc_world_profile_update(int w) { b2WorldId id = worlds_get(w); if (b2World_IsValid(id)) s_profile = b2World_GetProfile(id); else memset(&s_profile, 0, sizeof s_profile); }
LC_API double b2lc_world_profile_step(void)    { return (double)s_profile.step; }
LC_API double b2lc_world_profile_pairs(void)   { return (double)s_profile.pairs; }
LC_API double b2lc_world_profile_collide(void) { return (double)s_profile.collide; }
LC_API double b2lc_world_profile_solve(void)   { return (double)s_profile.solve; }
LC_API double b2lc_world_profile_refit(void)   { return (double)s_profile.refit; }
LC_API double b2lc_world_profile_sensors(void) { return (double)s_profile.sensors; }

static b2Counters s_counters;
LC_API void b2lc_world_counters_update(int w) { b2WorldId id = worlds_get(w); if (b2World_IsValid(id)) s_counters = b2World_GetCounters(id); else memset(&s_counters, 0, sizeof s_counters); }
LC_API int  b2lc_world_count_bodies(void)   { return s_counters.bodyCount; }
LC_API int  b2lc_world_count_shapes(void)   { return s_counters.shapeCount; }
LC_API int  b2lc_world_count_contacts(void) { return s_counters.contactCount; }
LC_API int  b2lc_world_count_joints(void)   { return s_counters.jointCount; }
LC_API int  b2lc_world_count_islands(void)  { return s_counters.islandCount; }

/* ------------------------------------------------------------------ */
/* Body: transforms, velocity-at-point, force/impulse-at-point, mass   */
/* ------------------------------------------------------------------ */
LC_API double b2lc_body_world_point_x(int b, double lx, double ly) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetWorldPoint(id, v2(lx, ly)).x : 0.0; }
LC_API double b2lc_body_world_point_y(int b, double lx, double ly) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetWorldPoint(id, v2(lx, ly)).y : 0.0; }
LC_API double b2lc_body_local_point_x(int b, double wx, double wy) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLocalPoint(id, v2(wx, wy)).x : 0.0; }
LC_API double b2lc_body_local_point_y(int b, double wx, double wy) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLocalPoint(id, v2(wx, wy)).y : 0.0; }
LC_API double b2lc_body_world_vector_x(int b, double lx, double ly) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetWorldVector(id, v2(lx, ly)).x : 0.0; }
LC_API double b2lc_body_world_vector_y(int b, double lx, double ly) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetWorldVector(id, v2(lx, ly)).y : 0.0; }
LC_API double b2lc_body_local_vector_x(int b, double wx, double wy) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLocalVector(id, v2(wx, wy)).x : 0.0; }
LC_API double b2lc_body_local_vector_y(int b, double wx, double wy) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLocalVector(id, v2(wx, wy)).y : 0.0; }
LC_API double b2lc_body_world_point_velocity_x(int b, double wx, double wy) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetWorldPointVelocity(id, v2(wx, wy)).x : 0.0; }
LC_API double b2lc_body_world_point_velocity_y(int b, double wx, double wy) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetWorldPointVelocity(id, v2(wx, wy)).y : 0.0; }
LC_API double b2lc_body_local_point_velocity_x(int b, double lx, double ly) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLocalPointVelocity(id, v2(lx, ly)).x : 0.0; }
LC_API double b2lc_body_local_point_velocity_y(int b, double lx, double ly) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLocalPointVelocity(id, v2(lx, ly)).y : 0.0; }

LC_API void b2lc_body_apply_force_at(int b, double fx, double fy, double px, double py, int wake) { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id) && finite2(fx, fy) && finite2(px, py)) b2Body_ApplyForce(id, v2(fx, fy), v2(px, py), wake ? true : false); }
LC_API void b2lc_body_apply_impulse_at(int b, double ix, double iy, double px, double py, int wake) { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id) && finite2(ix, iy) && finite2(px, py)) b2Body_ApplyLinearImpulse(id, v2(ix, iy), v2(px, py), wake ? true : false); }

LC_API double b2lc_body_rotational_inertia(int b) { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetRotationalInertia(id) : 0.0; }
LC_API double b2lc_body_local_center_x(int b)     { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLocalCenterOfMass(id).x : 0.0; }
LC_API double b2lc_body_local_center_y(int b)     { b2BodyId id = bodies_get(b); return b2Body_IsValid(id) ? (double)b2Body_GetLocalCenterOfMass(id).y : 0.0; }

/* mass-data stash (shared by body and shape mass-data getters) */
static b2MassData s_md;
LC_API void   b2lc_body_mass_data_update(int b) { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) s_md = b2Body_GetMassData(id); else memset(&s_md, 0, sizeof s_md); }
LC_API double b2lc_md_mass(void)     { return (double)s_md.mass; }
LC_API double b2lc_md_center_x(void) { return (double)s_md.center.x; }
LC_API double b2lc_md_center_y(void) { return (double)s_md.center.y; }
LC_API double b2lc_md_inertia(void)  { return (double)s_md.rotationalInertia; }
LC_API void b2lc_body_set_mass_data(int b, double mass, double cx, double cy, double inertia) {
    b2BodyId id = bodies_get(b);
    if (!b2Body_IsValid(id) || !finite2(cx, cy) || !finite2(mass, inertia)) return;
    if (mass < 0.0 || inertia < 0.0) return;
    b2MassData md; md.mass = (float)mass; md.center = v2(cx, cy); md.rotationalInertia = (float)inertia;
    b2Body_SetMassData(id, md);
}
LC_API void b2lc_body_apply_mass_from_shapes(int b) { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) b2Body_ApplyMassFromShapes(id); }

LC_API void b2lc_body_set_target_transform(int b, double x, double y, double angle, double dt) {
    b2BodyId id = bodies_get(b);
    if (!b2Body_IsValid(id) || !finite3(x, y, angle) || !positive(dt)) return;
    b2Transform t; t.p = v2(x, y); t.q = rotOf(angle);
    b2Body_SetTargetTransform(id, t, (float)dt);
}

LC_API void b2lc_body_enable_sleep(int b, int f)           { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) b2Body_EnableSleep(id, f ? true : false); }
LC_API int  b2lc_body_is_sleep_enabled(int b)             { b2BodyId id = bodies_get(b); return (b2Body_IsValid(id) && b2Body_IsSleepEnabled(id)) ? 1 : 0; }
LC_API int  b2lc_body_is_fixed_rotation(int b)            { b2BodyId id = bodies_get(b); return (b2Body_IsValid(id) && b2Body_IsFixedRotation(id)) ? 1 : 0; }
LC_API void b2lc_body_enable_contact_events(int b, int f)  { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) b2Body_EnableContactEvents(id, f ? true : false); }
LC_API void b2lc_body_enable_hit_events(int b, int f)      { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) b2Body_EnableHitEvents(id, f ? true : false); }

/* AABB stash (shared by body and shape AABB getters) */
static b2AABB s_aabb;
LC_API void   b2lc_body_aabb_update(int b) { b2BodyId id = bodies_get(b); if (b2Body_IsValid(id)) s_aabb = b2Body_ComputeAABB(id); else memset(&s_aabb, 0, sizeof s_aabb); }
LC_API double b2lc_aabb_lower_x(void) { return (double)s_aabb.lowerBound.x; }
LC_API double b2lc_aabb_lower_y(void) { return (double)s_aabb.lowerBound.y; }
LC_API double b2lc_aabb_upper_x(void) { return (double)s_aabb.upperBound.x; }
LC_API double b2lc_aabb_upper_y(void) { return (double)s_aabb.upperBound.y; }

/* body shape / joint enumeration (call _count to snapshot, then _at by index) */
static b2ShapeId *s_bShapes = NULL; static int s_bShapesCap = 0, s_bShapeCnt = 0;
static b2JointId *s_bJoints = NULL; static int s_bJointsCap = 0, s_bJointCnt = 0;
LC_API int b2lc_body_shape_count(int b) {
    b2BodyId id = bodies_get(b);
    if (!b2Body_IsValid(id)) { s_bShapeCnt = 0; return 0; }
    int n = b2Body_GetShapeCount(id);
    if (!grow_buffer((void **)&s_bShapes, &s_bShapesCap, n, sizeof(b2ShapeId))) { s_bShapeCnt = 0; return 0; }
    s_bShapeCnt = (n > 0) ? b2Body_GetShapes(id, s_bShapes, n) : 0;
    return s_bShapeCnt;
}
LC_API int b2lc_body_shape_at(int i) { return (i >= 0 && i < s_bShapeCnt) ? shape_h(s_bShapes[i]) : 0; }
LC_API int b2lc_body_joint_count(int b) {
    b2BodyId id = bodies_get(b);
    if (!b2Body_IsValid(id)) { s_bJointCnt = 0; return 0; }
    int n = b2Body_GetJointCount(id);
    if (!grow_buffer((void **)&s_bJoints, &s_bJointsCap, n, sizeof(b2JointId))) { s_bJointCnt = 0; return 0; }
    s_bJointCnt = (n > 0) ? b2Body_GetJoints(id, s_bJoints, n) : 0;
    return s_bJointCnt;
}
LC_API int b2lc_body_joint_at(int i) { return (i >= 0 && i < s_bJointCnt) ? joint_handle_of(s_bJoints[i]) : 0; }

/* ------------------------------------------------------------------ */
/* Shape: type/material/filter getters, event flags, geometry get/set, */
/* per-shape ray cast, AABB, closest point, mass data, sensor overlaps */
/* ------------------------------------------------------------------ */
LC_API int    b2lc_shape_type(int s)        { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? (int)b2Shape_GetType(id) : 0; }
LC_API int    b2lc_shape_is_sensor(int s)   { b2ShapeId id = shapes_get(s); return (b2Shape_IsValid(id) && b2Shape_IsSensor(id)) ? 1 : 0; }
LC_API double b2lc_shape_density(int s)     { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? (double)b2Shape_GetDensity(id) : 0.0; }
LC_API double b2lc_shape_friction(int s)    { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? (double)b2Shape_GetFriction(id) : 0.0; }
LC_API double b2lc_shape_restitution(int s) { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? (double)b2Shape_GetRestitution(id) : 0.0; }
LC_API int    b2lc_shape_material_id(int s) { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? b2Shape_GetMaterial(id) : 0; }
LC_API void   b2lc_shape_set_material_id(int s, int m) { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id)) b2Shape_SetMaterial(id, m); }

LC_API void b2lc_shape_set_filter(int s, double cat, double mask, int group) {
    b2ShapeId id = shapes_get(s);
    if (!b2Shape_IsValid(id) || !filter_bits_ok(cat) || !filter_bits_ok(mask)) return;
    b2Filter f; f.categoryBits = (uint64_t)cat; f.maskBits = (uint64_t)mask; f.groupIndex = group;
    b2Shape_SetFilter(id, f);
}
LC_API double b2lc_shape_filter_category(int s) { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? (double)b2Shape_GetFilter(id).categoryBits : 0.0; }
LC_API double b2lc_shape_filter_mask(int s)     { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? (double)b2Shape_GetFilter(id).maskBits : 0.0; }
LC_API int    b2lc_shape_filter_group(int s)    { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? b2Shape_GetFilter(id).groupIndex : 0; }

LC_API void b2lc_shape_enable_sensor_events(int s, int f)   { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id)) b2Shape_EnableSensorEvents(id, f ? true : false); }
LC_API int  b2lc_shape_are_sensor_events_enabled(int s)     { b2ShapeId id = shapes_get(s); return (b2Shape_IsValid(id) && b2Shape_AreSensorEventsEnabled(id)) ? 1 : 0; }
LC_API void b2lc_shape_enable_contact_events(int s, int f)  { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id)) b2Shape_EnableContactEvents(id, f ? true : false); }
LC_API int  b2lc_shape_are_contact_events_enabled(int s)    { b2ShapeId id = shapes_get(s); return (b2Shape_IsValid(id) && b2Shape_AreContactEventsEnabled(id)) ? 1 : 0; }
LC_API void b2lc_shape_enable_hit_events(int s, int f)      { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id)) b2Shape_EnableHitEvents(id, f ? true : false); }
LC_API int  b2lc_shape_are_hit_events_enabled(int s)        { b2ShapeId id = shapes_get(s); return (b2Shape_IsValid(id) && b2Shape_AreHitEventsEnabled(id)) ? 1 : 0; }
LC_API void b2lc_shape_enable_presolve_events(int s, int f) { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id)) b2Shape_EnablePreSolveEvents(id, f ? true : false); }

/* geometry getters: circle/capsule/segment share a small scalar stash.
 * A failed update (stale handle / wrong type) zeroes the stash so the
 * getters report 0 instead of leaking the previous shape's values. */
static double s_geom[5];
LC_API void   b2lc_shape_circle_update(int s)  { b2ShapeId id = shapes_get(s); memset(s_geom, 0, sizeof s_geom); if (b2Shape_IsValid(id) && b2Shape_GetType(id) == b2_circleShape) { b2Circle c = b2Shape_GetCircle(id); s_geom[0] = c.center.x; s_geom[1] = c.center.y; s_geom[2] = c.radius; } }
LC_API double b2lc_shape_circle_x(void)        { return s_geom[0]; }
LC_API double b2lc_shape_circle_y(void)        { return s_geom[1]; }
LC_API double b2lc_shape_circle_radius(void)   { return s_geom[2]; }
LC_API void   b2lc_shape_capsule_update(int s) { b2ShapeId id = shapes_get(s); memset(s_geom, 0, sizeof s_geom); if (b2Shape_IsValid(id) && b2Shape_GetType(id) == b2_capsuleShape) { b2Capsule c = b2Shape_GetCapsule(id); s_geom[0] = c.center1.x; s_geom[1] = c.center1.y; s_geom[2] = c.center2.x; s_geom[3] = c.center2.y; s_geom[4] = c.radius; } }
LC_API double b2lc_shape_capsule_x1(void)      { return s_geom[0]; }
LC_API double b2lc_shape_capsule_y1(void)      { return s_geom[1]; }
LC_API double b2lc_shape_capsule_x2(void)      { return s_geom[2]; }
LC_API double b2lc_shape_capsule_y2(void)      { return s_geom[3]; }
LC_API double b2lc_shape_capsule_radius(void)  { return s_geom[4]; }
LC_API void   b2lc_shape_segment_update(int s) { b2ShapeId id = shapes_get(s); memset(s_geom, 0, sizeof s_geom); if (b2Shape_IsValid(id) && b2Shape_GetType(id) == b2_segmentShape) { b2Segment g = b2Shape_GetSegment(id); s_geom[0] = g.point1.x; s_geom[1] = g.point1.y; s_geom[2] = g.point2.x; s_geom[3] = g.point2.y; } }
LC_API double b2lc_shape_segment_x1(void)      { return s_geom[0]; }
LC_API double b2lc_shape_segment_y1(void)      { return s_geom[1]; }
LC_API double b2lc_shape_segment_x2(void)      { return s_geom[2]; }
LC_API double b2lc_shape_segment_y2(void)      { return s_geom[3]; }

/* polygon geometry readback (up to 8 verts + radius) */
static b2Polygon s_polyRead;
LC_API int    b2lc_shape_polygon_update(int s) { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id) && b2Shape_GetType(id) == b2_polygonShape) { s_polyRead = b2Shape_GetPolygon(id); return s_polyRead.count; } s_polyRead.count = 0; return 0; }
LC_API int    b2lc_shape_polygon_count(void)   { return s_polyRead.count; }
LC_API double b2lc_shape_polygon_vx(int i)     { return (i >= 0 && i < s_polyRead.count) ? (double)s_polyRead.vertices[i].x : 0.0; }
LC_API double b2lc_shape_polygon_vy(int i)     { return (i >= 0 && i < s_polyRead.count) ? (double)s_polyRead.vertices[i].y : 0.0; }
LC_API double b2lc_shape_polygon_radius(void)  { return (double)s_polyRead.radius; }

/* geometry setters */
LC_API void b2lc_shape_set_circle(int s, double cx, double cy, double r) { b2ShapeId id = shapes_get(s); if (!b2Shape_IsValid(id) || !finite2(cx, cy) || !positive(r)) return; b2Circle c; c.center = v2(cx, cy); c.radius = (float)r; b2Shape_SetCircle(id, &c); }
LC_API void b2lc_shape_set_capsule(int s, double x1, double y1, double x2, double y2, double r) { b2ShapeId id = shapes_get(s); if (!b2Shape_IsValid(id) || !finite2(x1, y1) || !finite2(x2, y2) || !positive(r) || (x1 == x2 && y1 == y2)) return; b2Capsule c; c.center1 = v2(x1, y1); c.center2 = v2(x2, y2); c.radius = (float)r; b2Shape_SetCapsule(id, &c); }
LC_API void b2lc_shape_set_segment(int s, double x1, double y1, double x2, double y2) { b2ShapeId id = shapes_get(s); if (!b2Shape_IsValid(id) || !finite2(x1, y1) || !finite2(x2, y2) || (x1 == x2 && y1 == y2)) return; b2Segment g; g.point1 = v2(x1, y1); g.point2 = v2(x2, y2); b2Shape_SetSegment(id, &g); }
LC_API void b2lc_shape_set_polygon(int s) { b2ShapeId id = shapes_get(s); if (!b2Shape_IsValid(id) || s_polyCnt < 3) return; b2Hull hull = b2ComputeHull(s_poly, s_polyCnt); if (hull.count < 3) return; b2Polygon p = b2MakePolygon(&hull, 0.0f); b2Shape_SetPolygon(id, &p); }

/* per-shape ray cast (stash) */
static int    s_shapeRayHit = 0;
static double s_shapeRay[5];   /* px, py, nx, ny, fraction */
LC_API int b2lc_shape_raycast(int s, double x1, double y1, double x2, double y2) {
    s_shapeRayHit = 0; memset(s_shapeRay, 0, sizeof s_shapeRay);
    b2ShapeId id = shapes_get(s);
    if (!b2Shape_IsValid(id)) return 0;
    b2RayCastInput in; in.origin = v2(x1, y1); in.translation = v2(x2 - x1, y2 - y1); in.maxFraction = 1.0f;
    b2CastOutput out = b2Shape_RayCast(id, &in);
    if (out.hit) {
        s_shapeRayHit = 1;
        s_shapeRay[0] = out.point.x;  s_shapeRay[1] = out.point.y;
        s_shapeRay[2] = out.normal.x; s_shapeRay[3] = out.normal.y;
        s_shapeRay[4] = out.fraction;
    }
    return s_shapeRayHit;
}
LC_API double b2lc_shape_ray_x(void)        { return s_shapeRay[0]; }
LC_API double b2lc_shape_ray_y(void)        { return s_shapeRay[1]; }
LC_API double b2lc_shape_ray_normal_x(void) { return s_shapeRay[2]; }
LC_API double b2lc_shape_ray_normal_y(void) { return s_shapeRay[3]; }
LC_API double b2lc_shape_ray_fraction(void) { return s_shapeRay[4]; }

LC_API void   b2lc_shape_aabb_update(int s) { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id)) s_aabb = b2Shape_GetAABB(id); else memset(&s_aabb, 0, sizeof s_aabb); }
LC_API double b2lc_shape_closest_point_x(int s, double tx, double ty) { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? (double)b2Shape_GetClosestPoint(id, v2(tx, ty)).x : 0.0; }
LC_API double b2lc_shape_closest_point_y(int s, double tx, double ty) { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? (double)b2Shape_GetClosestPoint(id, v2(tx, ty)).y : 0.0; }
LC_API void   b2lc_shape_mass_data_update(int s) { b2ShapeId id = shapes_get(s); if (b2Shape_IsValid(id)) s_md = b2Shape_GetMassData(id); else memset(&s_md, 0, sizeof s_md); }

/* sensor overlaps (poll which shapes currently sit inside a sensor) */
static b2ShapeId *s_ov = NULL; static int s_ovCap = 0, s_ovCnt = 0;
LC_API int b2lc_shape_sensor_capacity(int s) { b2ShapeId id = shapes_get(s); return b2Shape_IsValid(id) ? b2Shape_GetSensorCapacity(id) : 0; }
LC_API int b2lc_shape_sensor_overlaps_update(int s) {
    s_ovCnt = 0;
    b2ShapeId id = shapes_get(s);
    if (!b2Shape_IsValid(id)) return 0;
    int cap = b2Shape_GetSensorCapacity(id);
    if (!grow_buffer((void **)&s_ov, &s_ovCap, cap, sizeof(b2ShapeId))) return 0;
    s_ovCnt = (cap > 0) ? b2Shape_GetSensorOverlaps(id, s_ov, cap) : 0;
    return s_ovCnt;
}
LC_API int b2lc_shape_sensor_overlap_count(void) { return s_ovCnt; }
LC_API int b2lc_shape_sensor_overlap_at(int i)   { return (i >= 0 && i < s_ovCnt) ? shape_h(s_ov[i]) : 0; }

/* ------------------------------------------------------------------ */
/* Chains (smooth multi-segment terrain). New handle table.            */
/* ------------------------------------------------------------------ */
#define LC_MAX_CHAIN 4096
static b2Vec2 s_chain[LC_MAX_CHAIN];
static int    s_chainCnt = 0;
static b2ShapeId *s_chainSeg = NULL; static int s_chainSegCap = 0, s_chainSegCnt = 0;
LC_API void b2lc_chain_begin(void) { s_chainCnt = 0; }
LC_API void b2lc_chain_add_point(double x, double y) { if (s_chainCnt < LC_MAX_CHAIN) s_chain[s_chainCnt++] = v2(x, y); }
static void retire_chain_segments(b2ChainId id) {
    if (!b2Chain_IsValid(id)) return;
    int n = b2Chain_GetSegmentCount(id);
    if (n <= 0) return;
    b2ShapeId *buf = (b2ShapeId *)malloc((size_t)n * sizeof(b2ShapeId));
    if (!buf) return;
    int got = b2Chain_GetSegments(id, buf, n);
    for (int i = 0; i < got; i++) retire_shape_id(buf[i]);
    free(buf);
}
static void register_chain_segments(b2ChainId id) {
    if (!b2Chain_IsValid(id)) return;
    int n = b2Chain_GetSegmentCount(id);
    if (n <= 0) return;
    b2ShapeId *buf = (b2ShapeId *)malloc((size_t)n * sizeof(b2ShapeId));
    if (!buf) return;
    int got = b2Chain_GetSegments(id, buf, n);
    for (int i = 0; i < got; i++) {
        if (shape_handle_of_id(buf[i]) == 0) (void)register_shape(buf[i]);
    }
    free(buf);
}
LC_API int b2lc_chain_create(int b, int isLoop, double friction, double restitution) {
    b2BodyId body = bodies_get(b);
    if (!b2Body_IsValid(body) || s_chainCnt < 4) return 0;
    b2ChainDef cd = b2DefaultChainDef();
    cd.points = s_chain;
    cd.count = s_chainCnt;
    b2SurfaceMaterial mat = b2DefaultSurfaceMaterial();
    mat.friction = (float)friction;
    mat.restitution = (float)restitution;
    cd.materials = &mat;
    cd.materialCount = 1;
    cd.isLoop = isLoop ? true : false;
    cd.enableSensorEvents = true;   /* let sensors detect terrain */
    if (s_sd.haveFilter) {
        cd.filter.categoryBits = (uint64_t)s_sd.catBits;
        cd.filter.maskBits     = (uint64_t)s_sd.maskBits;
        cd.filter.groupIndex   = s_sd.groupIndex;
    }
    b2ChainId id = b2CreateChain(body, &cd);
    reset_shapedef();
    int h = chains_add(id);
    if (!h) { if (b2Chain_IsValid(id)) b2DestroyChain(id); return 0; }
    register_chain_segments(id);
    return h;
}
LC_API void b2lc_chain_destroy(int c) {
    b2ChainId id = chains_get(c);
    if (b2Chain_IsValid(id)) {
        retire_chain_segments(id);
        b2DestroyChain(id);
    }
    chains_free_handle(c);
}
LC_API int  b2lc_chain_is_valid(int c)  { return b2Chain_IsValid(chains_get(c)) ? 1 : 0; }
LC_API void b2lc_chain_set_friction(int c, double f)    { b2ChainId id = chains_get(c); if (b2Chain_IsValid(id)) b2Chain_SetFriction(id, (float)f); }
LC_API double b2lc_chain_friction(int c)                { b2ChainId id = chains_get(c); return b2Chain_IsValid(id) ? (double)b2Chain_GetFriction(id) : 0.0; }
LC_API void b2lc_chain_set_restitution(int c, double r) { b2ChainId id = chains_get(c); if (b2Chain_IsValid(id)) b2Chain_SetRestitution(id, (float)r); }
LC_API double b2lc_chain_restitution(int c)             { b2ChainId id = chains_get(c); return b2Chain_IsValid(id) ? (double)b2Chain_GetRestitution(id) : 0.0; }
LC_API int b2lc_chain_segment_count(int c) {
    b2ChainId id = chains_get(c);
    if (!b2Chain_IsValid(id)) { s_chainSegCnt = 0; return 0; }
    int n = b2Chain_GetSegmentCount(id);
    if (!grow_buffer((void **)&s_chainSeg, &s_chainSegCap, n, sizeof(b2ShapeId))) { s_chainSegCnt = 0; return 0; }
    s_chainSegCnt = (n > 0) ? b2Chain_GetSegments(id, s_chainSeg, n) : 0;
    return s_chainSegCnt;
}
LC_API int b2lc_chain_segment_at(int i) { return (i >= 0 && i < s_chainSegCnt) ? shape_h(s_chainSeg[i]) : 0; }

/* ------------------------------------------------------------------ */
/* Joints: generic surface                                             */
/* ------------------------------------------------------------------ */
LC_API int    b2lc_joint_type(int j)             { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (int)b2Joint_GetType(id) : 0; }
LC_API int    b2lc_joint_body_a(int j)           { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? body_h(b2Joint_GetBodyA(id)) : 0; }
LC_API int    b2lc_joint_body_b(int j)           { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? body_h(b2Joint_GetBodyB(id)) : 0; }
LC_API double b2lc_joint_local_anchor_a_x(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2Joint_GetLocalAnchorA(id).x : 0.0; }
LC_API double b2lc_joint_local_anchor_a_y(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2Joint_GetLocalAnchorA(id).y : 0.0; }
LC_API double b2lc_joint_local_anchor_b_x(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2Joint_GetLocalAnchorB(id).x : 0.0; }
LC_API double b2lc_joint_local_anchor_b_y(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2Joint_GetLocalAnchorB(id).y : 0.0; }
LC_API int    b2lc_joint_get_collide_connected(int j)      { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2Joint_GetCollideConnected(id)) ? 1 : 0; }
LC_API void   b2lc_joint_set_collide_connected(int j, int f){ b2JointId id = joints_get(j); if (b2Joint_IsValid(id)) b2Joint_SetCollideConnected(id, f ? true : false); }
LC_API double b2lc_joint_constraint_force_x(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2Joint_GetConstraintForce(id).x : 0.0; }
LC_API double b2lc_joint_constraint_force_y(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2Joint_GetConstraintForce(id).y : 0.0; }
LC_API double b2lc_joint_constraint_torque(int j)  { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2Joint_GetConstraintTorque(id) : 0.0; }
LC_API void   b2lc_joint_wake_bodies(int j)        { b2JointId id = joints_get(j); if (b2Joint_IsValid(id)) b2Joint_WakeBodies(id); }

/* ---- Motor joint (drive bodyB to an offset pose from bodyA) -------- */
LC_API int b2lc_joint_motor(int w, int bA, int bB, double offX, double offY, double angOff,
                            double maxForce, double maxTorque, double corr, int collide) {
    b2WorldId wid = worlds_get(w);
    b2BodyId a = bodies_get(bA), b = bodies_get(bB);
    if (!b2World_IsValid(wid) || !b2Body_IsValid(a) || !b2Body_IsValid(b)) return 0;
    if (!finite3(offX, offY, angOff) || !finite3(maxForce, maxTorque, corr)) return 0;
    b2MotorJointDef jd = b2DefaultMotorJointDef();
    jd.bodyIdA = a; jd.bodyIdB = b;
    jd.linearOffset = v2(offX, offY);
    jd.angularOffset = (float)angOff;
    jd.maxForce = (float)maxForce;
    jd.maxTorque = (float)maxTorque;
    jd.correctionFactor = (float)corr;
    jd.collideConnected = collide ? true : false;
    return register_joint(b2CreateMotorJoint(wid, &jd));
}
LC_API void   b2lc_motor_set_linear_offset(int j, double x, double y) { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite2(x, y)) b2MotorJoint_SetLinearOffset(id, v2(x, y)); }
LC_API double b2lc_motor_linear_offset_x(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MotorJoint_GetLinearOffset(id).x : 0.0; }
LC_API double b2lc_motor_linear_offset_y(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MotorJoint_GetLinearOffset(id).y : 0.0; }
LC_API void   b2lc_motor_set_angular_offset(int j, double a) { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(a)) b2MotorJoint_SetAngularOffset(id, (float)a); }
LC_API double b2lc_motor_angular_offset(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MotorJoint_GetAngularOffset(id) : 0.0; }
LC_API void   b2lc_motor_set_max_force(int j, double f) { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(f) && f >= 0.0) b2MotorJoint_SetMaxForce(id, (float)f); }
LC_API double b2lc_motor_max_force(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MotorJoint_GetMaxForce(id) : 0.0; }
LC_API void   b2lc_motor_set_max_torque(int j, double t) { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(t) && t >= 0.0) b2MotorJoint_SetMaxTorque(id, (float)t); }
LC_API double b2lc_motor_max_torque(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MotorJoint_GetMaxTorque(id) : 0.0; }
LC_API void   b2lc_motor_set_correction_factor(int j, double c) { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(c)) b2MotorJoint_SetCorrectionFactor(id, (float)c); }
LC_API double b2lc_motor_correction_factor(int j) { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MotorJoint_GetCorrectionFactor(id) : 0.0; }

/* ---- Filter joint (disable collision between two specific bodies) -- */
LC_API int b2lc_joint_filter(int w, int bA, int bB) {
    b2WorldId wid = worlds_get(w);
    b2BodyId a = bodies_get(bA), b = bodies_get(bB);
    if (!b2World_IsValid(wid) || !b2Body_IsValid(a) || !b2Body_IsValid(b)) return 0;
    b2FilterJointDef jd = b2DefaultFilterJointDef();
    jd.bodyIdA = a; jd.bodyIdB = b;
    return register_joint(b2CreateFilterJoint(wid, &jd));
}

/* ---- Revolute joint: granular spring/limit/motor get+set ----------- */
LC_API void   b2lc_revolute_enable_spring(int j, int f)        { b2JointId id = joints_get(j); if (b2Joint_IsValid(id)) b2RevoluteJoint_EnableSpring(id, f ? true : false); }
LC_API int    b2lc_revolute_is_spring_enabled(int j)          { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2RevoluteJoint_IsSpringEnabled(id)) ? 1 : 0; }
LC_API void   b2lc_revolute_set_spring_hertz(int j, double hz) { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(hz) && hz >= 0.0) b2RevoluteJoint_SetSpringHertz(id, (float)hz); }
LC_API double b2lc_revolute_spring_hertz(int j)               { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2RevoluteJoint_GetSpringHertz(id) : 0.0; }
LC_API void   b2lc_revolute_set_spring_damping(int j, double d){ b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(d) && d >= 0.0) b2RevoluteJoint_SetSpringDampingRatio(id, (float)d); }
LC_API double b2lc_revolute_spring_damping(int j)            { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2RevoluteJoint_GetSpringDampingRatio(id) : 0.0; }
LC_API int    b2lc_revolute_is_limit_enabled(int j)          { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2RevoluteJoint_IsLimitEnabled(id)) ? 1 : 0; }
LC_API double b2lc_revolute_lower_limit(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2RevoluteJoint_GetLowerLimit(id) : 0.0; }
LC_API double b2lc_revolute_upper_limit(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2RevoluteJoint_GetUpperLimit(id) : 0.0; }
LC_API int    b2lc_revolute_is_motor_enabled(int j)          { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2RevoluteJoint_IsMotorEnabled(id)) ? 1 : 0; }
LC_API void   b2lc_revolute_set_motor_speed(int j, double s)  { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(s)) b2RevoluteJoint_SetMotorSpeed(id, (float)s); }
LC_API double b2lc_revolute_motor_speed(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2RevoluteJoint_GetMotorSpeed(id) : 0.0; }
LC_API double b2lc_revolute_motor_torque(int j)            { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2RevoluteJoint_GetMotorTorque(id) : 0.0; }
LC_API void   b2lc_revolute_set_max_motor_torque(int j, double t){ b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(t) && t >= 0.0) b2RevoluteJoint_SetMaxMotorTorque(id, (float)t); }
LC_API double b2lc_revolute_max_motor_torque(int j)        { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2RevoluteJoint_GetMaxMotorTorque(id) : 0.0; }

/* ---- Prismatic joint: granular spring/limit/motor get+set ---------- */
LC_API void   b2lc_prismatic_enable_spring(int j, int f)        { b2JointId id = joints_get(j); if (b2Joint_IsValid(id)) b2PrismaticJoint_EnableSpring(id, f ? true : false); }
LC_API int    b2lc_prismatic_is_spring_enabled(int j)          { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2PrismaticJoint_IsSpringEnabled(id)) ? 1 : 0; }
LC_API void   b2lc_prismatic_set_spring_hertz(int j, double hz) { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(hz) && hz >= 0.0) b2PrismaticJoint_SetSpringHertz(id, (float)hz); }
LC_API double b2lc_prismatic_spring_hertz(int j)               { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2PrismaticJoint_GetSpringHertz(id) : 0.0; }
LC_API void   b2lc_prismatic_set_spring_damping(int j, double d){ b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(d) && d >= 0.0) b2PrismaticJoint_SetSpringDampingRatio(id, (float)d); }
LC_API double b2lc_prismatic_spring_damping(int j)            { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2PrismaticJoint_GetSpringDampingRatio(id) : 0.0; }
LC_API int    b2lc_prismatic_is_limit_enabled(int j)          { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2PrismaticJoint_IsLimitEnabled(id)) ? 1 : 0; }
LC_API double b2lc_prismatic_lower_limit(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2PrismaticJoint_GetLowerLimit(id) : 0.0; }
LC_API double b2lc_prismatic_upper_limit(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2PrismaticJoint_GetUpperLimit(id) : 0.0; }
LC_API int    b2lc_prismatic_is_motor_enabled(int j)          { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2PrismaticJoint_IsMotorEnabled(id)) ? 1 : 0; }
LC_API void   b2lc_prismatic_set_motor_speed(int j, double s)  { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(s)) b2PrismaticJoint_SetMotorSpeed(id, (float)s); }
LC_API double b2lc_prismatic_motor_speed(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2PrismaticJoint_GetMotorSpeed(id) : 0.0; }
LC_API double b2lc_prismatic_motor_force(int j)            { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2PrismaticJoint_GetMotorForce(id) : 0.0; }
LC_API double b2lc_prismatic_max_motor_force(int j)        { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2PrismaticJoint_GetMaxMotorForce(id) : 0.0; }
LC_API double b2lc_prismatic_speed(int j)                  { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2PrismaticJoint_GetSpeed(id) : 0.0; }

/* ---- Distance joint: granular spring/limit/motor get+set ----------- */
LC_API int    b2lc_distance_is_spring_enabled(int j)         { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2DistanceJoint_IsSpringEnabled(id)) ? 1 : 0; }
LC_API double b2lc_distance_spring_hertz(int j)             { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2DistanceJoint_GetSpringHertz(id) : 0.0; }
LC_API double b2lc_distance_spring_damping(int j)           { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2DistanceJoint_GetSpringDampingRatio(id) : 0.0; }
LC_API int    b2lc_distance_is_limit_enabled(int j)         { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2DistanceJoint_IsLimitEnabled(id)) ? 1 : 0; }
LC_API double b2lc_distance_min_length(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2DistanceJoint_GetMinLength(id) : 0.0; }
LC_API double b2lc_distance_max_length(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2DistanceJoint_GetMaxLength(id) : 0.0; }
LC_API double b2lc_distance_current_length(int j)          { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2DistanceJoint_GetCurrentLength(id) : 0.0; }
LC_API void   b2lc_distance_enable_motor(int j, int f)       { b2JointId id = joints_get(j); if (b2Joint_IsValid(id)) b2DistanceJoint_EnableMotor(id, f ? true : false); }
LC_API int    b2lc_distance_is_motor_enabled(int j)         { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2DistanceJoint_IsMotorEnabled(id)) ? 1 : 0; }
LC_API void   b2lc_distance_set_motor_speed(int j, double s) { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(s)) b2DistanceJoint_SetMotorSpeed(id, (float)s); }
LC_API double b2lc_distance_motor_speed(int j)             { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2DistanceJoint_GetMotorSpeed(id) : 0.0; }
LC_API void   b2lc_distance_set_max_motor_force(int j, double f){ b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(f) && f >= 0.0) b2DistanceJoint_SetMaxMotorForce(id, (float)f); }
LC_API double b2lc_distance_max_motor_force(int j)        { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2DistanceJoint_GetMaxMotorForce(id) : 0.0; }
LC_API double b2lc_distance_motor_force(int j)            { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2DistanceJoint_GetMotorForce(id) : 0.0; }

/* ---- Weld joint: reference angle + per-axis stiffness getters ------ */
LC_API double b2lc_weld_reference_angle(int j)            { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WeldJoint_GetReferenceAngle(id) : 0.0; }
LC_API void   b2lc_weld_set_reference_angle(int j, double a){ b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(a)) b2WeldJoint_SetReferenceAngle(id, (float)a); }
LC_API double b2lc_weld_linear_hertz(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WeldJoint_GetLinearHertz(id) : 0.0; }
LC_API double b2lc_weld_linear_damping(int j)            { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WeldJoint_GetLinearDampingRatio(id) : 0.0; }
LC_API double b2lc_weld_angular_hertz(int j)             { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WeldJoint_GetAngularHertz(id) : 0.0; }
LC_API double b2lc_weld_angular_damping(int j)           { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WeldJoint_GetAngularDampingRatio(id) : 0.0; }

/* ---- Wheel joint: granular spring/limit/motor get+set -------------- */
LC_API int    b2lc_wheel_is_spring_enabled(int j)          { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2WheelJoint_IsSpringEnabled(id)) ? 1 : 0; }
LC_API double b2lc_wheel_spring_hertz(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WheelJoint_GetSpringHertz(id) : 0.0; }
LC_API double b2lc_wheel_spring_damping(int j)            { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WheelJoint_GetSpringDampingRatio(id) : 0.0; }
LC_API void   b2lc_wheel_enable_limit(int j, int f)        { b2JointId id = joints_get(j); if (b2Joint_IsValid(id)) b2WheelJoint_EnableLimit(id, f ? true : false); }
LC_API int    b2lc_wheel_is_limit_enabled(int j)          { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2WheelJoint_IsLimitEnabled(id)) ? 1 : 0; }
LC_API void   b2lc_wheel_set_limits(int j, double lo, double hi){ b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite2(lo, hi) && lo <= hi) b2WheelJoint_SetLimits(id, (float)lo, (float)hi); }
LC_API double b2lc_wheel_lower_limit(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WheelJoint_GetLowerLimit(id) : 0.0; }
LC_API double b2lc_wheel_upper_limit(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WheelJoint_GetUpperLimit(id) : 0.0; }
LC_API int    b2lc_wheel_is_motor_enabled(int j)          { b2JointId id = joints_get(j); return (b2Joint_IsValid(id) && b2WheelJoint_IsMotorEnabled(id)) ? 1 : 0; }
LC_API double b2lc_wheel_motor_speed(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WheelJoint_GetMotorSpeed(id) : 0.0; }
LC_API double b2lc_wheel_motor_torque(int j)            { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WheelJoint_GetMotorTorque(id) : 0.0; }
LC_API double b2lc_wheel_max_motor_torque(int j)        { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2WheelJoint_GetMaxMotorTorque(id) : 0.0; }

/* ---- Mouse joint: target + spring getters/setters ------------------ */
LC_API double b2lc_mouse_target_x(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MouseJoint_GetTarget(id).x : 0.0; }
LC_API double b2lc_mouse_target_y(int j)              { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MouseJoint_GetTarget(id).y : 0.0; }
LC_API void   b2lc_mouse_set_spring_hertz(int j, double hz)  { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(hz) && hz >= 0.0) b2MouseJoint_SetSpringHertz(id, (float)hz); }
LC_API double b2lc_mouse_spring_hertz(int j)          { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MouseJoint_GetSpringHertz(id) : 0.0; }
LC_API void   b2lc_mouse_set_spring_damping(int j, double d) { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(d) && d >= 0.0) b2MouseJoint_SetSpringDampingRatio(id, (float)d); }
LC_API double b2lc_mouse_spring_damping(int j)        { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MouseJoint_GetSpringDampingRatio(id) : 0.0; }
LC_API void   b2lc_mouse_set_max_force(int j, double f)      { b2JointId id = joints_get(j); if (b2Joint_IsValid(id) && finite1(f) && f >= 0.0) b2MouseJoint_SetMaxForce(id, (float)f); }
LC_API double b2lc_mouse_max_force(int j)             { b2JointId id = joints_get(j); return b2Joint_IsValid(id) ? (double)b2MouseJoint_GetMaxForce(id) : 0.0; }

/* ------------------------------------------------------------------ */
/* World queries: overlap / ray-cast-all / shape-cast.                 */
/* Box2D's queries are callback-based; we collect hits into one shared */
/* growable buffer (a C callback pushes each), then expose count +     */
/* indexed getters (the same idea as the ray/contact stashes above).   */
/* ------------------------------------------------------------------ */
typedef struct { int body, shape; double px, py, nx, ny, frac; } LcQRow;
static LcQRow *s_q = NULL; static int s_qCap = 0, s_qCnt = 0;
static void q_reset(void) { s_qCnt = 0; }
static void q_push(b2ShapeId sh, double px, double py, double nx, double ny, double f) {
    if (s_qCnt >= s_qCap) {
        int nc = s_qCap ? s_qCap * 2 : 64;
        if (!grow_buffer((void **)&s_q, &s_qCap, nc, sizeof(LcQRow))) return;
    }
    s_q[s_qCnt].shape = shape_h(sh);
    s_q[s_qCnt].body  = body_handle_of_shape(sh);
    s_q[s_qCnt].px = px; s_q[s_qCnt].py = py;
    s_q[s_qCnt].nx = nx; s_q[s_qCnt].ny = ny; s_q[s_qCnt].frac = f;
    s_qCnt++;
}
static bool overlap_cb(b2ShapeId shapeId, void *ctx) { (void)ctx; q_push(shapeId, 0, 0, 0, 0, 0); return true; }
static b2Vec2 s_qPoint;
static bool overlap_point_cb(b2ShapeId shapeId, void *ctx) {
    (void)ctx;
    if (b2Shape_TestPoint(shapeId, s_qPoint)) q_push(shapeId, s_qPoint.x, s_qPoint.y, 0, 0, 0);
    return true;
}
static float cast_cb(b2ShapeId shapeId, b2Vec2 point, b2Vec2 normal, float fraction, void *ctx) {
    (void)ctx; q_push(shapeId, point.x, point.y, normal.x, normal.y, fraction); return 1.0f;  /* gather all */
}
static int q_cmp_frac(const void *a, const void *b) {
    double fa = ((const LcQRow *)a)->frac, fb = ((const LcQRow *)b)->frac;
    return (fa < fb) ? -1 : (fa > fb) ? 1 : 0;
}

LC_API int b2lc_query_overlap_aabb(int w, double x1, double y1, double x2, double y2) {
    q_reset();
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid)) return 0;
    b2AABB aabb;
    aabb.lowerBound = v2(x1 < x2 ? x1 : x2, y1 < y2 ? y1 : y2);
    aabb.upperBound = v2(x1 > x2 ? x1 : x2, y1 > y2 ? y1 : y2);
    b2World_OverlapAABB(wid, aabb, b2DefaultQueryFilter(), overlap_cb, NULL);
    return s_qCnt;
}
LC_API int b2lc_query_overlap_point(int w, double x, double y) {
    q_reset();
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid)) return 0;
    s_qPoint = v2(x, y);
    const float e = 0.001f;
    b2AABB aabb; aabb.lowerBound = v2(x - e, y - e); aabb.upperBound = v2(x + e, y + e);
    b2World_OverlapAABB(wid, aabb, b2DefaultQueryFilter(), overlap_point_cb, NULL);
    return s_qCnt;
}
LC_API int b2lc_query_overlap_circle(int w, double cx, double cy, double r) {
    q_reset();
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid)) return 0;
    b2Vec2 pt = v2(cx, cy);
    b2ShapeProxy proxy = b2MakeProxy(&pt, 1, (float)r);
    b2World_OverlapShape(wid, &proxy, b2DefaultQueryFilter(), overlap_cb, NULL);
    return s_qCnt;
}
LC_API int b2lc_query_overlap_shape(int w, double radius) {
    q_reset();
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid) || s_polyCnt < 1) return 0;
    b2ShapeProxy proxy = b2MakeProxy(s_poly, s_polyCnt, (float)radius);
    b2World_OverlapShape(wid, &proxy, b2DefaultQueryFilter(), overlap_cb, NULL);
    return s_qCnt;
}
LC_API int b2lc_query_raycast_all(int w, double x1, double y1, double x2, double y2) {
    q_reset();
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid)) return 0;
    b2World_CastRay(wid, v2(x1, y1), v2(x2 - x1, y2 - y1), b2DefaultQueryFilter(), cast_cb, NULL);
    if (s_qCnt > 1) qsort(s_q, (size_t)s_qCnt, sizeof(LcQRow), q_cmp_frac);
    return s_qCnt;
}
LC_API int b2lc_query_shapecast(int w, double radius, double dx, double dy) {
    q_reset();
    b2WorldId wid = worlds_get(w);
    if (!b2World_IsValid(wid) || s_polyCnt < 1) return 0;
    b2ShapeProxy proxy = b2MakeProxy(s_poly, s_polyCnt, (float)radius);
    b2World_CastShape(wid, &proxy, v2(dx, dy), b2DefaultQueryFilter(), cast_cb, NULL);
    if (s_qCnt > 1) qsort(s_q, (size_t)s_qCnt, sizeof(LcQRow), q_cmp_frac);
    return s_qCnt;
}
LC_API int    b2lc_query_count(void)      { return s_qCnt; }
LC_API int    b2lc_query_body(int i)      { return (i >= 0 && i < s_qCnt) ? s_q[i].body  : 0; }
LC_API int    b2lc_query_shape(int i)     { return (i >= 0 && i < s_qCnt) ? s_q[i].shape : 0; }
LC_API double b2lc_query_x(int i)         { return (i >= 0 && i < s_qCnt) ? s_q[i].px : 0.0; }
LC_API double b2lc_query_y(int i)         { return (i >= 0 && i < s_qCnt) ? s_q[i].py : 0.0; }
LC_API double b2lc_query_normal_x(int i)  { return (i >= 0 && i < s_qCnt) ? s_q[i].nx : 0.0; }
LC_API double b2lc_query_normal_y(int i)  { return (i >= 0 && i < s_qCnt) ? s_q[i].ny : 0.0; }
LC_API double b2lc_query_fraction(int i)  { return (i >= 0 && i < s_qCnt) ? s_q[i].frac : 0.0; }

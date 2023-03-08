一、Lock和Condition

> 我们知道，Java中的`synchronized`的实现就是采用的`管程`技术，那么Java SDK 并发包中的`Lock`和`Condition`是基于什么技术实现的呢？
>
> `Lock`和`Condition`的实现也是采用的`管程`技术，`Lock`用于解决互斥问题，`Condition`用于解决同步问题。既然 Java 从语言层面已经实现了管程了，那为什么还要在 SDK 里提供另外一种实现呢？

## 再造管程的理由

> 在学习破坏死锁产生的条件时，`synchronized`是隐式加锁解锁的，如果获取不到锁，线程阻塞，什么都做不了，所以无法通过`synchronized`破坏“不可抢占”条件。
>
> 如果我们重新设计一把互斥锁去解决这个问题，那该怎么设计呢？我觉得有三种方案。
>
> * 1、**能够响应中断**。synchronized 的问题是，持有锁 A 后，如果尝试获取锁 B 失败，那么 线程就进入阻塞状态，一旦发生死锁，就没有任何机会来唤醒阻塞的线程。但如果阻塞 状态的线程能够响应中断信号，也就是说当我们给阻塞的线程发送中断信号的时候，能 够唤醒它，那它就有机会释放曾经持有的锁 A。这样就破坏了不可抢占条件了。
> * 2、**支持超时**。如果线程在一段时间之内没有获取到锁，不是进入阻塞状态，而是返回一个 错误，那这个线程也有机会释放曾经持有的锁。这样也能破坏不可抢占条件。
> * 3、**非阻塞地获取锁**。如果尝试获取锁失败，并不进入阻塞状态，而是直接返回，那这个线 程也有机会释放曾经持有的锁。这样也能破坏不可抢占条件。
>
> 这三个方案全面拟补了`synchronized`的不足，也是Lock接口的三个方法，详情如下：
>
> ```java
> // 支持中断的API
> void lockInterruptibly() throws InterruptedException;
> 
> // 支持超时的API
> boolean tryLock(long time, TimeUnit unit) throws InterruptedException;
> 
> // 支持非阻塞获取锁的API
> boolean tryLock();
> ```

## 如何保证可见性

> 我们知道知道 Java 里多线程的可见性是通过 Happens-Before 规则保证的，而 synchronized 之所以能够保证可见性，也是因为有一条 synchronized 相关的规则：**synchronized 的解锁 Happens-Before 于后续对这个锁 的加锁**。
>
> 那 Java SDK 里面 Lock 靠什么保证可见性呢？
>
> Java SDK 里面的 ReentrantLock 、CountDownlatch等等并发工具都是基于AbstractQueuedSynchronizer 实现的，AbstractQueuedSynchronizer内部持有一个 volatile 的成员变量 state，获取锁的时候，会读写 state 的值；解锁的时候，也会读写 state 的值（简化后的代码如下面所示）。
>
> ```java
> class SampleLock {
> 	volatile int state;
>  	// 加锁
>  	lock() {
>  		// 省略代码无数
>  		state = 1;
>  	}
>  	// 解锁
>  	unlock() {
>  		// 省略代码无数
>  		state = 0;
>  	}
> }
> ```
>
> 根据相关的 Happens-Before 规则：
>
> * 顺序性规则：在一个线程中，按照程序顺序，前面的操作Happens-Before于后续的任意操作。
> * volatile变量规则：指对于一个volatile 变量的写操作，Happens-Before于后续对这个volatile 变量的读操作，代表禁用缓存。
> * 传递性规则：如果A `Happens-Before`B，且B`Happens-Before`C，那么A`Happens-Before`C。
>
> 所以**Lock的可靠性是利用了 volatile 相关的 Happens-Before 规则**实现的。同时当同一个线程多次加锁后，state也会随之增加；多次解锁后，state也会随之减少。state=0时代表锁已经全部释放。所以**Lock支持可重入**。
>
> 在使用 ReentrantLock 的时候，你会发现 ReentrantLock 这个类有两个构造函数，一个是 无参构造函数，一个是传入 fair 参数的构造函数。fair 参数代表的是锁的公平策略，如果传 入 true 就表示需要构造一个公平锁，反之则表示要构造一个非公平锁。
>
> ```java
> // 无参构造函数：默认非公平锁
> public ReentrantLock() {
>  	sync = new NonfairSync();
> }
> // 根据公平策略参数创建锁
> public ReentrantLock(boolean fair){
>  	sync = fair ? new FairSync() : new NonfairSync();
> }
> ```

## 用锁的最佳实践

> 用锁虽然能解决很多并发问题，但是风险也是挺高的。可能会导致死锁，也可能影响性能。推荐的三个用锁的最佳实践，它们分别是：
>
> * 1、永远只在更新对象的成员变量时加锁
> * 2、永远只在访问可变的成员变量时加锁
> * 3、永远不在调用其他对象的方法时加锁

## 同步与异步

> 其实在编程领域，异步的场景还是挺多的，比如 TCP 协议本身就是异步的，我们工作中经常用到的 RPC 调用，在 TCP 协议层面，发送完 RPC 请求后，线程是不会等待 RPC 的响应结果的。**通俗点来讲就是调用方是否需要等待结果，如果需要等待结果，就是同步；如果不需要等待结果，就是异步**。同步，是 Java 代码默认的处理方式。如果你想让你的程序支持异步，可以通过下面两种方 式来实现：
>
> * 调用方创建一个子线程，在子线程中执行方法调用，这种调用我们称为异步调用；
> * 方法实现的时候，创建一个新的线程执行主要逻辑，主线程直接 return，这种方法我们 一般称为异步方法。
>
> 实际在日常开发中，我们使用RPC框架调用其他服务都是同步的，这是为什么呢？其实很简单，一定是有人帮你做了异步转同步的事情。例如目前知名的 RPC 框架 Dubbo 就给我们做了异步转同步的事情。

# 二、Semaphore：如何快速实现一个限流器？

> Semaphore，翻译成中文就是信号量。信号量是由大名鼎鼎的计算机科学家迪杰斯特拉（Dijkstra）于 1965 年提出，在这之后的 15 年，信号量一直都是并发编程领域的终结者，直到 1980 年管程被提出来，我们才有了第二选择。

## 信号量模型

> 信号量模型还是很简单的，可以简单概括为：**一个计数器**，**一个等待队列**，**三个方法**。在信 号量模型里，计数器和等待队列对外是透明的，所以只能通过信号量模型提供的三个方法来 访问它们，这三个方法分别是：init()、down() 和 up()。你可以结合下图来形象化地理解。
>
> ![image-20221114111151832](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211141113027.png)
>
> * init()：设置计数器的初始值。
> * down()：计数器的值减 1；如果此时计数器的值小于 0，则当前线程将被阻塞，否则当前线程可以继续执行。
> * up()：计数器的值加 1；如果此时计数器的值小于或者等于 0，则唤醒等待队列中的一个 线程，并将其从等待队列中移除。

## Java提供的Semaphtore

>在 Java SDK 里面，信号量模型是由 java.util.concurrent.Semaphore 实现的，Semaphore 这个类能够保证这三个方法都是原子操作。信号量模型里面的down()、up() 这两个操作，在 Java SDK 并发包中的 Semaphore 的 acquire() 和 release()。
>
>### 使用Semaphtore实现互斥锁
>
>下面是使用 java.util.concurrent.Semaphore 实现互斥锁的代码：
>
>```java
>public class SemaphoreMutex {
>
>    private int count;
>
>    /**
>     * 运行通行数量为1的信号量
>     */
>    private static final Semaphore semaphore = new Semaphore(1);
>
>    public void addOne(int i) {
>        try {
>            semaphore.acquire();
>            System.out.println("Thread " + i + " 获取互斥锁");
>            count += 1;
>            Thread.sleep(1000);
>            System.out.println("Thread " + i + " 当前结果为：" + count);
>        } catch (InterruptedException e) {
>            e.printStackTrace();
>        } finally {
>            semaphore.release();
>            System.out.println("Thread " + i + " 释放互斥锁");
>        }
>    }
>
>
>    public static void main(String[] args) {
>        long start = System.currentTimeMillis();
>        SemaphoreMutex semaphoreMutex = new SemaphoreMutex();
>        List<Integer> list = new ArrayList<>();
>        for(int i = 1 ; i<=1000; i++){
>            list.add(i);
>        }
>        CompletableFuture[] array = list.stream().map(item ->             CompletableFuture.runAsync(() -> semaphoreMutex.addOne(item)))
>                .toArray(CompletableFuture[]::new);
>        CompletableFuture.allOf(array).join();
>
>        long end = System.currentTimeMillis();
>        System.out.println("总耗时为：" + (end - start));
>        System.out.println("最后结果为：" + semaphoreMutex.count);
>    }
>}
>```
>
>### 使用Semaphore实现限流器
>
>上面的例子，我们用信号量实现了一个最简单的互斥锁功能。你是不有一个疑问，Java SDK里面提供了Lock，为什么还要提供一个Semaphore呢？
>
>其实**Semaphore不仅可以实现互斥锁，Semaphore最主要的功能是可以允许多个线程访问一个临界区**。
>
>举个例子，一张餐桌有4个座位，只能保证4个人同时就餐，其他人只能等到餐桌上的某个人吃完，才能争抢空出来的位置。而Semaphore的作用就等于椅子的数量，而餐桌为共享资源。
>
>既然生活中都有这样的场景，那么工作中肯定也不会缺少的。比如我们服务器资源有限，同时接收请求数量最大为1000个。当高峰期时，用户量庞大，极有可能出现同时有20000万个请求到达服务端。同时接收这些请求必然会影响服务稳定性，甚至出现服务器崩盘。我们可以利用Semaphore制作一个限流器，控制同时访问服务器的最大数量，超出限流数量的请求阻塞，等到有请求完成，再允许其他请求进入。下面是使用Semaphore实现限流器的代码：
>
>```java
>public class CurrentLimitDevice<T>{
>
>    private final Semaphore semaphore;
>
>
>    public CurrentLimitDevice(int size) {
>        this.semaphore = new Semaphore(size);
>    }
>
>    public void run(Consumer<T> consumer, T param) throws InterruptedException {
>        semaphore.acquire();
>        try {
>            consumer.accept(param);
>        } finally {
>            semaphore.release();
>        }
>    }
>
>    public static void main(String[] args) {
>        CurrentLimitDevice<String> currentLimitDevice2 = new CurrentLimitDevice<String>(10);
>        try {
>            currentLimitDevice2.run(System.out::println, "GJK");
>        } catch (InterruptedException e) {
>            e.printStackTrace();
>        }
>    }
>}
>```
>
>再举个栗子，我们工作中遇到的各种池化资源，例如连 接池、对象池、线程池等等，在同一时刻，一定是允许多个线程同时使用连接池的，当然，每个连接在被释放前，是不允许其他线程使用的。
>
>假如让我们去设计一个对象池，我们该怎么做呢？所谓对象池呢，指的是一次性创建出 N 个对象，之后所有的线程重复利用这 N 个对象，当然对象在被释放前，也是不允许其他线程使用的。对象池，可以用 List 保存实例对象，这个很简单。限流器的设计，我们可以用信号量这一解决方案。下面是对象池的示例代码：
>
>```java
>public class ObjectPool<T,R> {
>
>    private final List<T> pool;
>
>    private final Semaphore semaphore1;
>
>
>
>
>    /**
>     * 构造方法，用于初始化对象池
>     * @param size
>     * @param t
>     */
>    public ObjectPool(int size, T t) {
>        this.pool = new Vector<T>();
>        for(int i=0;i<size;i++){
>            this.pool.add(t);
>        }
>        this.semaphore1 = new Semaphore(size);
>    }
>
>
>
>    public R exec(Function<T,R> function) throws InterruptedException {
>        semaphore1.acquire();
>        T t =null;
>        try {
>            t = pool.remove(0);
>            return function.apply(t);
>        } finally {
>            pool.add(t);
>            semaphore1.release();
>        }
>    }
>
>
>    public static void main(String[] args) {
>        ObjectPool<Long, String> pool = new ObjectPool<Long, String>(10, 2L);
>        try {
>            pool.exec(t -> {
>                System.out.println(t);
>                return t.toString();
>            });
>        } catch (InterruptedException e) {
>            e.printStackTrace();
>        }
>    }
>}
>```
>
>我们用一个`List`来保存对象实例，用`Semaphore`实现限流器。关键代码是``exec()``方法，这个方法里面实现了限流功能。在这个方法里，我先调用`acquire()`方法，假设对象池大小是10，信号量的计数器初始化为10，那么前10个线程调用`acquire()`方法，都能继续执行，相当于通过了信号灯，而其他线程则会阻塞在`acquire()`方法上。对于通过信号灯的线程，我们为每一个线程分配一个对象t，分配完之后执行回调函数`function`，而函数的参数正是全面分配的对象t；执行完回调函数之后，他们就会释放对象，同时调用`release()`方法来更新信号量的计数器。如果此时信号量里计数器的值小于等于0，那么说明有线程在等待，此时会自动唤醒等待的线程。

# 三、 ReadWriteLock：如何快速实现一个完备的缓存

> 在我们日常开发中，有一种非常普遍的并发场景：读多写少场景。实际工作中，为了优化性能，我们经常会使用缓存，例如缓存元数据、缓存基础数据等，这就是一种典型的读多写少应用场景。缓存之所以能提升性能，一个重要的条件就是缓存的数据一定是读多写少的，例如元数据和基础数据基本上不会发生变化（写少），但是使用它们的地方却很多（读多）。
>
> 针对读多写少这种并发场景，Java SDK 并发包提供了读写锁——ReadWriteLock，非常容易使用，并且性能很好。

## 什么是读写锁

> 读写锁，并不是 Java 语言特有的，而是一个广为使用的通用技术，所有的读写锁都遵守以下三条基本原则：
>
> * 1、允许多个线程同时读共享变量；
> * 2、只允许一个线程写共享变量；
> * 3、如果一个写线程正在执行写操作，此时禁止读线程读共享变量。
>
> 读写锁与互斥锁的一个重要区别就是**读写锁允许多个线程同时读共享变量**，而互斥锁是不允许的，这是读写锁在读多写少场景下性能优于互斥锁的关键。但**读写锁的写操作是互斥的**， 当一个线程在写共享变量的时候，是不允许其他线程执行写操作和读操作。

## 快速实现一个缓存

> 下面我们就实践起来，用 ReadWriteLock 快速实现一个通用的缓存工具类。
>
> ```java
> public class AllCache <K,V>{
> 
>     /**
>      * 缓存
>      */
>     private final Map<K,V> cache = new HashMap<>();
> 
>     /**
>      * 新建读写锁
>      */
>     private final ReentrantReadWriteLock readWriteLock = new ReentrantReadWriteLock();
> 
>     /**
>      * 读锁
>      */
>     private final ReentrantReadWriteLock.ReadLock readLock = readWriteLock.readLock();
> 
>     /**
>      * 写锁
>      */
>     private final ReentrantReadWriteLock.WriteLock writeLock = readWriteLock.writeLock();
> 
> 
> 
>     /**
>      * 从缓存获取数据
>      * @param k
>      * @return
>      */
>     public V get(K k){
>         readLock.lock();
>         try {
>             return cache.get(k);
>         } finally {
>             readLock.unlock();
>         }
>     }
> 
>     /**
>      * 数据写入缓存
>      * @param k
>      * @param v
>      */
>     public void put(K k, V v){
>         writeLock.lock();
>         try {
>             cache.put(k,v);
>         } finally {
>             writeLock.unlock();
>         }
>     }
> 
> }
> ```
>
> 在上面的代码中，我们声明了一个 `Cache` 类，其中类型参数` K `代表缓存里 `key` 的 类型，`V `代表缓存里 `value` 的类型。缓存的数据保存在 `Cache` 类内部的 `HashMap` 里面， HashMap 不是线程安全的，这里我们使用读写锁 `ReadWriteLock` 来保证其线程安全。`Cache` 这个工具类，我们提供了两个方法，一个是读缓存方法 `get()`，另一个是写缓存方法 `put()`。

## 实现缓存的按需加载

> **使用缓存首先要解决缓存数据的初始化问题**，缓存的初始化可以采用一次性加载，也可以使用按需加载的方式。
>
> 如果源头数据的数据量不大，就可以采用一次性加载的方式，这种方式最简单（可参考下图），只需在应用启动的时候把源头数据查询出来，依次调用类似上面示例代码中的 put() 方法就可以了。
>
> ![image-20221115152415158](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211151525301.png)
>
> 如果源头数据量非常大，那么就需要按需加载了，按需加载也叫懒加载，指的是只有当应用 查询缓存，并且数据不在缓存里的时候，才触发加载源头相关数据进缓存的操作。如何利用 ReadWriteLock 来实现缓存的按需加载，我们可以参考下图。
>
> ![image-20221115152426137](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211151525389.png)
>
> 实现按需加载的缓存，我们要注意：
>
> * 如果缓存中没有缓存目标对象，那么就需要从数据库中加载，然后写入缓存，写缓存需要用到写锁。
> * 在获取写锁之后，不要直接去查询数据库，重新验证了一次缓存中是否存在，再次验证如果还是不存在，我们才去查询数据库并更新本地缓存。
>
> ```java
> public class LazyCache<K, V> {
> 
>     /**
>      * 缓存，用于存放数据
>      */
>     private final Map<K, V> cache = new HashMap<>();
> 
>     /**
>      * 初始化读写锁
>      */
>     private final ReentrantReadWriteLock readWriteLock = new ReentrantReadWriteLock();
> 
>     /**
>      * 读锁
>      */
>     private final ReentrantReadWriteLock.ReadLock readLock = readWriteLock.readLock();
> 
>     /**
>      * 读锁
>      */
>     private final ReentrantReadWriteLock.WriteLock writeLock = readWriteLock.writeLock();
> 
> 
>     /**
>      * 读缓存
>      *
>      * @param key
>      * @return
>      */
>     public V get(K key, Function<K, V> function) {
>         //读缓存
>         readLock.lock();
>         V v;
>         try {
>             v = cache.get(key);
>         } finally {
>             readLock.unlock();
>         }
> 
>         //缓存存在数据，直接返回
>         if (v != null) {
>             return v;
>         }
> 
>         //写缓存
>         writeLock.lock();
>         try {
>             //再次判断缓存是否已经有值，在获取到写锁之前，有可能有其他线程写入缓存了
>             v = cache.get(key);
>             if (v == null) {
>                 //缓存不存在数据，通过回调获取
>                 v = function.apply(key);
>                 cache.put(key, v);
>             }
>         } finally {
>             writeLock.unlock();
>         }
>         return v;
>     }
> 
> }
> ```
>
> 第一个注意点很好理解，但是第二个注意点是为什么呢？
>
> 假设在高并发场景下，有可能会有多线程竞争写锁。假设缓存是空的，没有缓存任何东西，如果此时有三个线程 T1、T2 和 T3 同时调用 get() 方法，并且参数 key 也是相同的。如果它们同时执行到46行获取写锁的时候，此时只有一个线程能够获得写锁。假设是线程 T1，线程 T1 获取写锁之后查询数据库并更新缓存，最终释放写锁。此时线程 T2 和 T3 会再有一个线程能够获取写锁，假设是 T2，如果不采用再次验证的方式，此时 T2 会再次查询数据库。T2 释放写锁之后，T3 也会再次查询一次数据库。而实际上线程 T1 已经把缓存的值设置好了，T2、T3 完全没有必要再次查询数据库。所以，再次验证的方式，能够避免高并发场景下重复查询数据的问题。

## 读写锁的升级与降级

> 上面按需加载的示例代码中，我们改造一下：
>
> ```java
>     /**
>      * 读缓存
>      *
>      * @param key
>      * @return
>      */
>     public V get(K key, Function<K, V> function) {
>         //读缓存
>         readLock.lock();
>         V v;
>         try {
>             v = cache.get(key);
>             //缓存存在数据，直接返回
>             if (v == null) {
>                 //写缓存
>                 writeLock.lock();
>                 try {
>                     //再次判断缓存是否已经有值，在获取到写锁之前，有可能有其他线程写入缓存了
>                     v = cache.get(key);
>                     if (v == null) {
>                         //缓存不存在数据，通过回调获取
>                         v = function.apply(key);
>                         cache.put(key, v);
>                     }
>                 } finally {
>                     writeLock.unlock();
>                 }
>             }
>         } finally {
>             readLock.unlock();
>         }
>         return v;
>     }
> ```
>
> 我们将写锁放到读锁内部。先获取读锁，缓存如果没有数据，哉获取写锁，查数据写入缓存，写锁解锁，读锁解锁，整个流程如上所述。这样看上去好像是没有问题的，但是我们忘了一项原则：**如果有一个写线程正在执行写操作，此时禁止读线程读共享变量**。在上面的代码示例中，读锁还没有释放，此时获取写锁，会导致写锁永久等待，最终导致相关线程都被阻塞，永远也没有机会被唤醒，所以**读写锁是不允许锁升级的**。
>
> 不过，虽然锁的升级是不允许的，但是锁的降级却是允许的。下面是根据ReentrantReadWriteLock 官方提供的示例改造而来。
>
> ```java
> public class LockUpOrDown<K, V> {
> 
>     /**
>      * 缓存，用于存放数据
>      */
>     private final Map<K, V> cache = new HashMap<>();
> 
>     /**
>      * 初始化读写锁
>      */
>     private final ReentrantReadWriteLock readWriteLock = new ReentrantReadWriteLock();
> 
>     /**
>      * 读锁
>      */
>     private final ReentrantReadWriteLock.ReadLock readLock = readWriteLock.readLock();
> 
>     /**
>      * 写锁
>      */
>     private final ReentrantReadWriteLock.WriteLock writeLock = readWriteLock.writeLock();
> 
>     /**
>      * 锁升级，读写锁不支持
>      *
>      * @param key
>      * @return
>      */
>     public void get(K key, Function<K, V> function, Consumer<V> consumer) {
>         //读加锁
>         readLock.lock();
>         V v;
>         try {
>             v = cache.get(key);
>             //缓存不存在数据
>             if (v == null) {
>                 readLock.unlock();
>                 //写缓存
>                 writeLock.lock();
>                 try {
>                     //再次判断缓存是否已经有值，在获取到写锁之前，有可能有其他线程写入缓存了
>                     v = cache.get(key);
>                     if (v == null) {
>                         //缓存不存在数据，通过回调获取
>                         v = function.apply(key);
>                         cache.put(key, v);
>                     }
>                     //锁降级，获取读锁
>                     readLock.lock();
>                 } finally {
>                     writeLock.unlock();
>                 }
>             }
>             consumer.accept(v);
>         } finally {
>             readLock.unlock();
>         }
>     }
>     
> }
> 
> ```

# 四、 CountDownLatch和CyclicBarrier：如何让多线程步调一致？

> 在线商城中，一般都会有对账系统，用户通过在线商城下单，会生成电子订单，保存在订单库；之后物流会生成派送单给用户发货，派送单保存在派送单库。为了防止漏派送或者重复派送，对账系统每天还会校验是否存在异常订单。对账系统业务逻辑如下：首先查询订单，然后查询派送单，之后对比订单和派送单，将差异写入差异库。
>
> ![image-20221121162323350](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211211623129.png)
>
> 对账系统的代码抽象之后，也很简单，核心代码如下，就是在一个单线程里面循环查询订 单、派送单，然后执行对账，最后将写入差异库。
>
> ```java
> while(存在未对账订单){
>     
>     // 查询未对账订单
>     pos = getPOrders();
>     
>     // 查询派送单
>     dos = getDOrders();
>     
>     // 执行对账操作
>     diff = check(pos, dos);
>     
>     // 差异写入差异库
>     save(diff);
> } 
> ```
>
> 我们根据对账伪代码，编写一个demo
>
> ```java
> public class Set {
> 
>     public static void main(String[] args) throws InterruptedException {
>         // 查询未对账订单
>         List<String> pos = Stream.of("1", "2", "3", "4").collect(Collectors.toList());
>         
>         // 查询派送单
>         List<String> dos =  Stream.of("1", "2", "3").collect(Collectors.toList());
> 
>         // 执行对账操作
>         list1.removeAll(list2);
>         
>         // 差异写入差异库
>         System.out.println(JSON.toJSONString(list1));
>     }
> }
> ```
>
> 当订单数据量和派送单数据量增大后，查询方法的执行效率必然会下降。如何才能提高性能呢？

## 利用并行优化对账系统

> 上面的案例中是单线程实现，所以执行过程有一定的顺序性。但是查询未对账订单和查询派送单两个环节是没有先后顺序的，我们可以用多线程方式异步查询，伪代码如下：
>
> ```java
> while(存在未对账订单){
>     // 查询未对账订单
>     Thread T1 = new Thread(()->{
>         pos = getPOrders();
>     });
>     T1.start();
>     
>     // 查询派送单
>     Thread T2 = new Thread(()->{
>         dos = getDOrders();
>     });
>     T2.start();
>     
>     // 等待 T1、T2 结束
>     T1.join();
>     T2.join();
>     
>     // 执行对账操作
>     diff = check(pos, dos);
>     
>     // 差异写入差异库
>     save(diff);
> } 
> 
> ```
>
> 根据上面伪代码，编写一个demo
>
> ```java
> public class Set {
> 
>     public static void main(String[] args) throws InterruptedException {
>         //未对账订单
>         AtomicReference<List<String>> pos = new AtomicReference<>();
>         
>         //派送单 
>         AtomicReference<List<String>> dos = new AtomicReference<>();
>         
>         // 查询未对账订单
>         Thread thread1 = new Thread(() -> pos.set(Stream.of("1", "2", "3", "4").collect(Collectors.toList())));
>         
>        // 查询派送单
>         Thread thread2 = new Thread(() -> dos.set(Stream.of("1", "2", "3").collect(Collectors.toList())));
>         
>         thread1.start();
>         thread2.start();
>         
>         // 等待线程pos、线程dos执行完毕
>         thread1.join();
>         thread2.join();
>         
>         // 执行对账操作
>         List<String> list1 = pos.get();
>         List<String> list2 = dos.get();
>         list1.removeAll(list2);
>         
>         // 差异写入差异库
>         System.out.println(JSON.toJSONString(list1));
>     }
> }
> ```

## 用 CountDownLatch 实现线程等待

> 经过上面的优化之后，基本上可以实现提升性能，但还是有点美中不足。while 循环里面每次都会创建新的线程，而创建线程可是个耗时的操作。所以最好是创建出来的线程能够循环利用，线程池就能解决这个问题。
>
> 线程池配合Java 并发包里已经提供了实现类似功能的工具类：CountDownLatch，我们尝试一下。我们首先创建了一个 `CountDownLatch`，计数器的初始值等于 `2`，之后 在`pos = getPOrders();`和`dos = getDOrders();`两条语句的后面对计数器执行减 1 操作，这个对计数器减 1 的操作是通过调用 `latch.countDown();` 来实现的。在主线程 中，我们通过调用 `latch.await()` 来实现对计数器等于 0 的等待。
>
> ```java
> // 创建 2 个线程的线程池
> Executor executor = Executors.newFixedThreadPool(2);
> 
> while(存在未对账订单){
>  // 计数器初始化为 2
>  CountDownLatch latch = new CountDownLatch(2);
>  // 查询未对账订单
>  executor.execute(()-> {
>      pos = getPOrders();
>      latch.countDown();
>  });
>  // 查询派送单
>  executor.execute(()-> {
>      dos = getDOrders();
>      latch.countDown();
>  });
> 
>  // 等待两个查询操作结束
>  latch.await();
> 
>  // 执行对账操作
>  diff = check(pos, dos);
>  
>  // 差异写入差异库
>  save(diff);
> }
> 
> ```
>
> 根据上面伪代码，编写一个demo：
>
> ```java
> public class DuiZhang {
>  public static final ExecutorService EXECUTOR = new ThreadPoolExecutor(
>          2,
>          4,
>          1L,
>          TimeUnit.MINUTES,
>          new LinkedBlockingQueue<>(16),
>          new ThreadFactoryBuilder().setNameFormat("duiZhang-%d").build(),
>          new ThreadPoolExecutor.CallerRunsPolicy());
> 
> 
>  public static void main(String[] args) throws ExecutionException, InterruptedException {
>      CountDownLatch countDownLatch = new CountDownLatch(2);
> 
>      AtomicReference<List<String>> pos = new AtomicReference<>();
>      AtomicReference<List<String>> dos = new AtomicReference<>();
>      EXECUTOR.execute(() -> {
>          pos.set(Stream.of("1", "2", "3", "4").collect(Collectors.toList()));
>          countDownLatch.countDown();
>      });
>      EXECUTOR.submit(() -> {
>          dos.set(Stream.of("1", "2", "3").collect(Collectors.toList()));
>          countDownLatch.countDown();
>      });
> 
>      countDownLatch.await();
> 
>      List<String> list1 = pos.get();
>      List<String> list2 = dos.get();
>      list1.removeAll(list2);
> 
>      System.out.println(JSON.toJSONString(list1));
>  }
> 
>  //public static void main(String[] args) throws ExecutionException, InterruptedException {
>  //
>  //    Future<List<String>> future1 = EXECUTOR.submit(() -> {
>  //        System.out.println("future1线程");
>  //        return Stream.of("1", "2", "3", "4").collect(Collectors.toList());
>  //    });
>  //    Future<List<String>> future2 = EXECUTOR.submit(() -> {
>  //        //countDownLatch.countDown();
>  //        System.out.println("future2线程");
>  //        return Stream.of("1", "2", "3").collect(Collectors.toList());
>  //    });
>  //    
>  //    List<String> list1 = future1.get();
>  //    List<String> list2 = future2.get();
>  //    list1.removeAll(list2);
>  //
>  //    System.out.println(JSON.toJSONString(list1));
>  //    System.out.println("main线程");
>  //}
> }
> ```
>
> 我们将 `查询未对账订单` 和 `查询派送单` 这两个查询操作并行了，但这两个查询操作和 对账操作 `check()`、`save() `之间还是串行的，过程如下图所示：
>
> ![image-20221128132544797](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211281511216.png)
>
> 那查询操作和对账操作可不可以并行处理呢？也就是说，在执行对账操作的时候，可以同时去执行下一轮的查询操作，这个过程可以形象化地表述为下面这幅示意图。
>
> ![image-20221128115855689](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211281511649.png)

## 用 CyclicBarrier 实现线程同步

> 上述的示意图，转为文字，描述如下：线程 T1 和线程 T2 只有都生产完 1 条数据的时候， 才能一起向下执行，也就是说，线程 T1 和线程 T2 要互相等待，步调要一致；同时当线程 T1 和 T2 都生产完一条数据的时候，还要能够通知线程 T3 执行对账操作。
>
> 两次查询操作能够和对账操作并行，对账操作还依赖查询操作的结果，这明显有点生产者 - 消费者的意思，两次查询操作是生产者， 对账操作是消费者。既然是生产者 - 消费者模型，那就需要有个队列，来保存生产者生产 的数据，而消费者则从这个队列消费数据。
>
> 这个方案的难点有两个：一个是线程 T1 和 T2 要做到 步调一致，另一个是要能够通知到线程 T3。
>
> Java 并发包里也已经提供了相关的工具类：CyclicBarrier，可以通过CyclicBarrier实现线程T1和线程T2步调一致，和通知线程T3工作。
>
> ```java
> // 订单队列
> Vector<P> pos;
> 
> // 派送单队列
> Vector<D> dos;
> 
> // 执行回调的线程池
> Executor executor = Executors.newFixedThreadPool(1);
> final CyclicBarrier barrier = new CyclicBarrier(2, ()->{
>     executor.execute(()->check());
>  });
> 
> void check(){
>     P p = pos.remove(0);
>     D d = dos.remove(0);
>     // 执行对账操作
>     diff = check(p, d);
>     // 差异写入差异库
>     save(diff);
> }
> 
> void checkAll(){
>     // 循环查询订单库
>     Thread T1 = new Thread(()->{
>         while(存在未对账订单){
>             // 查询订单库
>             pos.add(getPOrders());
>             // 等待
>             barrier.await();
>         }     
>     });
>     T1.start();
>     
>     // 循环查询运单库
>     Thread T2 = new Thread(()->{
>         while(存在未对账订单){
>             // 查询运单库
>             dos.add(getDOrders());
>             // 等待
>             barrier.await();
>         }
>     });
>     T2.start();
> }
> ```
>
> 根据上面伪代码，编写一个demo：
>
> ```java
> public class DuiZhang {
> 
>     private final Vector<AtomicReference<List<String>>> posVector = new Vector<>();
>     
>     private final Vector<AtomicReference<List<String>>> dosVector = new Vector<>();
> 
>     public final ExecutorService executor = new ThreadPoolExecutor(
>             2,
>             4,
>             1L,
>             TimeUnit.MINUTES,
>             new LinkedBlockingQueue<>(16),
>             new ThreadFactoryBuilder().setNameFormat("duiZhang-%d").build(),
>             new ThreadPoolExecutor.CallerRunsPolicy());
> 
>     public final CyclicBarrier cyclicBarrier = new CyclicBarrier(2, this::check);
> 
> 
>     public void main(String[] args) {
>         DuiZhang duiZhang = new DuiZhang();
>         AtomicReference<List<String>> pos = new AtomicReference<>();
>         AtomicReference<List<String>> dos = new AtomicReference<>();
>         duiZhang.executor.execute(() -> {
>             pos.set(Stream.of("1", "2", "3", "4").collect(Collectors.toList()));
>             posVector.add(pos);
>             try {
>                 duiZhang.cyclicBarrier.await();
>             } catch (Exception e) {
>                 e.printStackTrace();
>             }
>         });
> 
>         duiZhang.executor.execute(() -> {
>             dos.set(Stream.of("1", "2", "3").collect(Collectors.toList()));
>             dosVector.add(dos);
>             try {
>                 duiZhang.cyclicBarrier.await();
>             } catch (Exception e) {
>                 e.printStackTrace();
>             }
>         });
> 
>     }
> 
>     private void check() {
>         AtomicReference<List<String>> pos = posVector.remove(0);
>         AtomicReference<List<String>> dos = dosVector.remove(0);
>         List<String> list1 = pos.get();
>         List<String> list2 = dos.get();
>         list1.removeAll(list2);
> 
>         System.out.println(JSON.toJSONString(list1));
>     }
> }
> ```

>总结：CountDownLatch 和 CyclicBarrier 是 Java 并发包提供的两个非常易用的线程同步工具 类，这两个工具类用法的区别在这里还是有必要再强调一下：**CountDownLatch 主要用来解决一个线程等待多个线程的场景**，可以类比旅游团团长要等待所有的游客到齐才能去下一 个景点；而**CyclicBarrier 是一组线程之间互相等待**，更像是几个驴友之间不离不弃。除此之外 **CountDownLatch 的计数器是不能循环利用的**，也就是说一旦计数器减到 0，再有线程调用 await()，该线程会直接通过。但**CyclicBarrier 的计数器是可以循环利用的**，而且具备自动重置的功能，一旦计数器减到 0 会自动重置到你设置的初始值。除此之外，**CyclicBarrier 还可以设置回调函数**，可以说是功能丰富。

#  五、并发容器：都有哪些“坑”需要我们填？

> Java 在 1.5 版本之前所谓的线程安全的容器，主要指的就是同步容器。不过同步容器有个 最大的问题，那就是性能差，所有方法都用 synchronized 来保证互斥，串行度太高了。因此 Java 在 1.5 及之后版本提供了性能更高的容器，我们一般称为并发容器。
>
> 并发容器虽然数量非常多，但依然是前面我们提到的四大类：List、Map、Set 和 Queue，下面的并发容器关系图，基本上把我们经常用的容器都覆盖到了。
>
> ![image-20221128151150843](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211281512877.png)

## List

> List 里面只有一个实现类就是**CopyOnWriteArrayList**。CopyOnWrite，顾名思义就是写 的时候会将共享变量新复制一份出来，这样做的好处是读操作完全无锁。
>
> 那 CopyOnWriteArrayList 的实现原理是怎样的呢？
>
> CopyOnWriteArrayList 内部维护了一个数组，成员变量 array 就指向这个内部数组，所有的读操作都是基于 array 进行的，如下图所示，迭代器 Iterator 遍历的就是 array 数组。
>
> ![image-20221128151401393](C:\Users\gaojiankang\AppData\Roaming\Typora\typora-user-images\image-20221128151401393.png)
>
> 如果在遍历 array 的同时，还有一个写操作，例如增加元素，CopyOnWriteArrayList 会将 array 复制一份，然后在新复制处理的数组上执行增加元素的操作，执行完之后再将 array 指向这个新的数组。通过下图你可以看到，读写是可以并行的，遍历操作一直都是基于原 array 执行，而写操作则是基于新 array 进行。
>
> ![image-20221128151504806](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211281515931.png)
>
> 使用 CopyOnWriteArrayList 需要注意的“坑”主要有两个方面。一个是应用场景， CopyOnWriteArrayList 仅适用于写操作非常少的场景，而且能够容忍读写的短暂不一致。 例如上面的例子中，写入的新元素并不能立刻被遍历到。另一个需要注意的是， CopyOnWriteArrayList 迭代器是只读的，不支持增删改。因为迭代器遍历的仅仅是一个快照，而对快照进行增删改是没有意义的。

## Map

> Map 接口的两个实现是 ConcurrentHashMap 和 ConcurrentSkipListMap，它们从应用 的角度来看，主要区别在于**ConcurrentHashMap 的 key 是无序的，而 ConcurrentSkipListMap 的 key 是有序的**。所以如果你需要保证 key 的顺序，就只能使用 ConcurrentSkipListMap。
>
> 使用 ConcurrentHashMap 和 ConcurrentSkipListMap 需要注意的地方是，它们的 key 和 value 都不能为空，否则会抛出NullPointerException这个运行时异常。下面这个表格总结了 Map 相关的实现类对于 key 和 value 的要求。
>
> ![image-20221128171643571](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211281716414.png)
>
> ConcurrentSkipListMap 里面的 SkipList 本身就是一种数据结构，中文一般都翻译为“跳 表”。**跳表插入、删除、查询操作平均的时间复杂度是 O(log n)**，理论上和并发线程数没有关系，所以在并发度非常高的情况下，若你对 ConcurrentHashMap 的性能还不满意， 可以尝试一下 ConcurrentSkipListMap。

## Set

> Set 接口的两个实现是 CopyOnWriteArraySet 和 ConcurrentSkipListSet，使用场景可以参考前面讲述的 CopyOnWriteArrayList 和 ConcurrentSkipListMap，它们的原理都是一样的，这里就不再赘述了。

## Queue

> Java 并发包里面 Queue 这类并发容器是最复杂的，你可以从以下两个维度来分类。一个维度是阻塞与非阻塞，所谓阻塞指的是当队列已满时，入队操作阻塞；当队列已空时，出队操作阻塞。另一个维度是单端与双端，单端指的是只能队尾入队，队首出队；而双端指的是 队首队尾皆可入队出队。Java 并发包里阻塞队列都用 Blocking 关键字标识，单端队列使 用 Queue 标识，双端队列使用 Deque 标识。
>
> 这两个维度组合后，可以将 Queue 细分为四大类，分别是：
>
> * 1、单端阻塞队列
>
> 实现有ArrayBlockingQueue、LinkedBlockingQueue、 SynchronousQueue、LinkedTransferQueue、PriorityBlockingQueue 和 DelayQueue。内部一般会持有一个队列，这个队列可以是数（ArrayBlockingQueue）,也可以是链表（ LinkedBlockingQueue）；甚至还可以不持有队列（SynchronousQueue），此时生产者线程的入队操作必须等待消费者线程的出队操作。而 LinkedTransferQueue 融合 LinkedBlockingQueue 和 SynchronousQueue 的功能，性能比 LinkedBlockingQueue 更好； PriorityBlockingQueue 支持按照优先级出队；DelayQueue 支持延时出队。
>
> ![image-20221128171628551](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211281716972.png)
>
> * 2、双端阻塞队列
>
> 实现有LinkedBlockingDeque。
>
> ![image-20221128171805226](C:\Users\gaojiankang\AppData\Roaming\Typora\typora-user-images\image-20221128171805226.png)
>
> * 3、单端非阻塞队列。
>
> 实现有ConcurrentLinkedQueue
>
> * 4、双端非阻塞队列。
>
> 实现有 ConcurrentLinkedDeque。
>
> 另外，使用队列时，需要格外注意队列是否支持有界（所谓有界指的是内部的队列是否有容 量限制）。实际工作中，一般都不建议使用无界的队列，因为数据量大了之后很容易导致 OOM。上面我们提到的这些 Queue 中，只有 **ArrayBlockingQueue** 和 **LinkedBlockingQueue** 是支持有界的，所以在使用其他无界队列时，一定要充分考虑是否存在导致 OOM 的隐患。

# 六、原子类：无锁工具类的典范

> 在这个例子中，add10K() 这个方法不是线程安全的，问题就出在变量 count 的可见性和 count+=1 的原子性上。可见性问题可以用 volatile 来解决，而原子性问题我们前面一直都是采用的互斥锁方案。
>
> ```java
> public class Test {
>     
>     long count = 0;
> 
>     void add10K() {
>         int idx = 0;
>         while(idx++ < 10000) {
>             count += 1;
>         }
>     }
> }
> 
> ```
>
> 其实对于简单的原子性问题，还有一种无锁方案。Java SDK 并发包将这种无锁方案封装提炼之后，实现了一系列的原子类。无锁方案相对互斥锁方案，最大的好处就是性能。互斥锁方案为了保证互斥性，需要执行加锁、解锁操作，而加锁、解锁操作本身就消耗性能；同时拿不到锁的线程还会进入阻塞状态，进而触发线程切换，线程切换对性能的消耗也很大。 相比之下，无锁方案则完全没有加锁、解锁的性能消耗，同时还能保证互斥性，既解决了问题，又没有带来新的问题，可谓绝佳方案。那它是如何做到的呢？

## 无锁方案的实现原理

> 其实原子类性能高的秘密很简单，硬件支持而已。CPU 为了解决并发问题，提供了 CAS 指 令（CAS，全称是 Compare And Swap，即“比较并交换”）。CAS 指令包含 3 个参 数：**共享变量的内存地址 A、用于比较的值 B 和共享变量的新值 C；并且只有当内存中地 址 A 处的值等于 B 时，才能将内存中地址 A 处的值更新为新值 C**。作为一条 CPU 指令， CAS 指令本身是能够保证原子性的。使用 CAS 来解决并发问题，一般都会伴随着自旋，而所谓自旋，其实就是循环尝试。
>
> 根据CAS工作原理编写CAS的模拟代码
>
> ```java
> public class SimulatedCAS {
> 
>     private volatile int count;
> 
>     void addOne(){
>         while (!cas(count, count+1)){
>         }
>     }
> 
>     synchronized boolean cas(int expectValue, int newValue){
>         //获取当前值
>         int curValue = count;
>         //期望值等于当前值，修改count，返回true
>         if(curValue == expectValue){
>             count = newValue;
>             return true;
>         }
>         //否则返回false
>         return false;
>     }
> }
> ```
>
> CAS 这种无锁方案，完全没有加锁、解锁操作，相对于互斥 锁方案来说，性能好了很多。但是在 CAS 方案中，有一个问题可能会常被忽略，那就是**ABA**的问题。
>
> 如果 cas(count,newValue) 返回的值不等于true，意味着线程在执行cas之前，count 的值被其他线程更新过。如果 cas(count,newValue) 返回的值等于true，是否意味着线程在执行cas之前，count 的值没有被其他线程更新过呢？显然不是的。举个例子，count初始值为0，线程A执行cas之前，线程B先一步执行了cas将count值修改为1，然后线程C也执行了cas将值修改成0。等到线程A执行cas时，虽然count的值为0，但是其实已经被其他线程更新过了，这就是 ABA 问题。

## 看 Java 如何实现原子化的 count += 1

> 前面我们提到了addOne方法，现在我们用AtomicLong原子类的 getAndIncrement() 方法替代了 count += 1，从而实现了线程安全。
>
> ```java
> public class Test {
>     
>     AtomicLong count = new AtomicLong(0);
>     
>     void add10K() {
>         int idx = 0;
>         while(idx++ < 10000) {
>             count.getAndIncrement();
>         }
>     }
> }
> 
> ```
>
> 原子类 AtomicLong 的 getAndIncrement() 方法 内部就是基于 CAS 实现的，下面我们来看看 Java 是如何使用 CAS 来实现原子化的count += 1的。
>
> 在 Java 1.8 版本中，getAndIncrement() 方法会转调 unsafe.getAndAddLong() 方法。 这里 this 和 valueOffset 两个参数可以唯一确定共享变量的内存地址。
>
> ```java
>     public final long getAndIncrement() {
>         return unsafe.getAndAddLong(this, valueOffset, 1L);
>     }
> ```
>
> unsafe.getAndAddLong() 方法的源码如下，该方法首先会在内存中读取共享变量的值， 之后循环调用 compareAndSwapLong() 方法来尝试设置共享变量的值，直到成功为止。 compareAndSwapLong() 是一个 native 方法，只有当内存中共享变量的值等于 expected 时，才会将共享变量的值更新为 x，并且返回 true；否则返回 fasle。 compareAndSwapLong 的语义和 CAS 指令的语义的差别仅仅是返回值不同而已。
>
> ```java
> public final long getAndAddLong(Object o, long offset, long delta){
>         long v;
>         do {
>                 // 读取内存中的值
>                 v = getLongVolatile(o, offset);
>         } while (!compareAndSwapLong(o, offset, v, v + delta));
>         return v;
> }
> 
> // 原子性地将变量更新为 x
> // 条件是内存中的值等于 expected
> // 更新成功则返回 true
> native boolean compareAndSwapLong(
>     Object o, long offset,
>     long expected,
>     long x);
> 
> ```
>
> 另外，需要注意的是，getAndAddLong() 方法的实现，基本上就是 CAS 使用的经典范例。所以请你再次体会下面这段抽象后的代码片段，它在很多无锁程序中经常出现。
>
> ```java
> do {
>     // 获取当前值
>     oldV = xxxx；
>         // 根据当前值计算新值
>         newV = ...oldV...
> }while(!compareAndSet(oldV,newV);
> ```

## 原子类概览

> Java SDK 并发包里提供的原子类内容很丰富，我们可以将它们分为五个类别：**原子化的基本数据类型**、**原子化的对象引用类型**、**原子化数组**、**原子化对象属性更新器**和**原子化的累加器**。
>
> ![image-20221129152737091](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211291707461.png)

### 原子化的基本数据类型

> 相关实现有 AtomicBoolean、AtomicInteger 和 AtomicLong，提供的方法主要有以下这些，详情可以参考 SDK 的源代码
>
> ```java
> getAndIncrement() // 原子化 i++
>     
> getAndDecrement() // 原子化的 i--
>     
> incrementAndGet() // 原子化的 ++i
>     
> decrementAndGet() // 原子化的 --i
>     
> // 当前值 +=delta，返回 += 前的值
> getAndAdd(delta)
>     
> // 当前值 +=delta，返回 += 后的值
> addAndGet(delta)
>     
> //CAS 操作，返回是否成功
> compareAndSet(expect, update)
>     
> // 以下四个方法
> // 新值可以通过传入 func 函数来计算
> getAndUpdate(func)
> updateAndGet(func)
> getAndAccumulate(x,func)
> accumulateAndGet(x,func)
> ```

### 原子化的对象引用类型

> 相关实现有 AtomicReference、AtomicStampedReference 和 AtomicMarkableReference，利用它们可以实现对象引用的原子化更新。
>
> AtomicReference 提供的方法和原子化的基本数据类型差不多。不过需要注意的是，对象引用的更新需要重点关注 ABA 问题，AtomicStampedReference 和 AtomicMarkableReference 这两个原子类可以解决 ABA 问题。解决 ABA 问题的思路其实很简单，增加一个版本号维度就可以了。
>
> AtomicStampedReference 实现的 CAS 方 法就增加了版本号参数，方法签名如下：
>
> ```java
> boolean compareAndSet(
>     V expectedReference,
>     V newReference,
>     int expectedStamp,
>     int newStamp) 
> ```
>
> AtomicMarkableReference 的实现机制则更简单，将版本号简化成了一个 Boolean 值， 方法签名如下：
>
> ```java
> boolean compareAndSet(
>     V expectedReference,
>     V newReference,
>     boolean expectedMark,
>     boolean newMark)
> ```

### 原子化数组

> 相关实现有 AtomicIntegerArray、AtomicLongArray 和 AtomicReferenceArray，利用 这些原子类，我们可以原子化地更新数组里面的每一个元素。这些类提供的方法和原子化的 基本数据类型的区别仅仅是：每个方法多了一个数组的索引参数。

### 原子化对象属性更新器

> 相关实现有 AtomicIntegerFieldUpdater、AtomicLongFieldUpdater 和 AtomicReferenceFieldUpdater，利用它们可以原子化地更新对象的属性，这三个方法都是利用反射机制实现的，创建更新器的方法如下：
>
> ```java
>     public static <U> AtomicIXXXFieldUpdater<U> newUpdater(Class<U> tclass, String fieldName) {
>         . . .
>     }
> ```
>
> 需要注意的是，**对象属性必须是 volatile 类型的，只有这样才能保证可见性**；
>
>  newUpdater() 的方法参数只有类的信息，没有对象的引用，而更新对象的属 性，一定需要对象的引用，那这个参数是在哪里传入的呢？是在原子操作的方法参数中传入 的。例如 compareAndSet() 这个原子操作
>
> ```java
> boolean compareAndSet(
>     T obj,
>     int expect,
>     int update)
> 
> ```

### 原子化的累加器

> DoubleAccumulator、DoubleAdder、LongAccumulator 和 LongAdder，这四个类仅 仅用来执行累加操作，相比原子化的基本数据类型，速度更快，但是不支持 compareAndSet() 方法。如果你仅仅需要累加操作，使用原子化的累加器性能会更好。

# 七、Executor与线程池：如何创建正确的线程池

> 虽然在 Java 语言中创建线程看上去就像创建一个对象一样简单，只需要 new Thread() 就 可以了，但实际上创建线程远不是创建一个对象那么简单。创建对象，仅仅是在 JVM 的堆 里分配一块内存而已；而创建一个线程，却需要调用操作系统内核的 API，然后操作系统要为线程分配一系列的资源，这个成本就很高了，所以**线程是一个重量级的对象，应该避免频繁创建和销毁**。
>
> 那如何避免呢？应对方案估计你已经知道了，那就是**线程池**。
>
> 

## 线程池是一种生产者 - 消费者模式

> 线程池的设计，没有办法直接采用一般意义上池化资源的设计方法。目前业界线程池的设计，普遍采用的都是生产者 - 消费者模式。线程池的使用方是生产者，线程池本身是消费者。在下面的示例代码中，我们创建了一个非常简单的线程池 MyThreadPool，你可以通过它来理解线程池的工作原理。
>
> ```java
> public class MyThreadPool {
> 
>     /**
>      * 阻塞队列
>      */
>     private BlockingQueue<Runnable> workQueue;
> 
>     /**
>      * 线程池大小
>      */
>     private List<WorkThread> threads;
> 
>     public MyThreadPool(BlockingQueue<Runnable> workQueue, int size) {
>         this.workQueue = workQueue;
>         this.threads = new ArrayList<>(size);
>         for (int i=0; i<size;i++){
>             WorkThread workThread = new WorkThread("WorkThread" + i);
>             workThread.run();
>             this.threads.add(workThread);
>         }
>     }
> 
> 
>     /**
>      * 提交任务的方法
>      * @param runnable
>      * @throws InterruptedException
>      */
>     public void execute(Runnable runnable) throws InterruptedException {
>         this.workQueue.put(runnable);
>     }
> 
> 
>     /**
>      * 工作线程内部类
>      */
>     private class WorkThread extends Thread {
> 
>         public WorkThread(String name) {
>             super(name);
>         }
> 
>         @SneakyThrows
>         @Override
>         public void run() {
>             while (true){
>                 Runnable task = workQueue.take();
>                 task.run();
>             }
>         }
>     }
> }
> 
> 
> 
> 
> /** 下面是使用示例 **/
> // 创建有界阻塞队列
> BlockingQueue<Runnable> workQueue = new LinkedBlockingQueue<>(2);
> // 创建线程池
> MyThreadPool pool = new MyThreadPool(10, workQueue);
> // 提交任务
> pool.execute(()->{
>     System.out.println("hello");
> });
> 
> ```
>
> 在 MyThreadPool 的内部，我们维护了一个阻塞队列 workQueue 和一组工作线程，工作线程的个数由构造函数中的 size来指定。用户通过调用 execute() 方法来提交 Runnable 任务，execute() 方法的内部实现仅仅是将任务加入到 workQueue 中。 MyThreadPool 内部维护的工作线程会循环消费 workQueue 中的任务并执行任务，线程池主要的工作原理就这些。

## 如何使用 Java 中的线程池

> Java 并发包里提供的线程池，远比我们上面的示例代码强大得多，当然也复杂得多。Java 提供的线程池相关的工具类中，最核心的是ThreadPoolExecutor，通过名字你也能看出来，它强调的是 Executor，而不是一般意义上的池化资源。
>
> ThreadPoolExecutor 的构造函数非常复杂，如下面代码所示，这个最完备的构造函数有 7 个参数。
>
> ```java
>     public ThreadPoolExecutor(int corePoolSize,
>                               int maximumPoolSize,
>                               long keepAliveTime,
>                               TimeUnit unit,
>                               BlockingQueue<Runnable> workQueue,
>                               ThreadFactory threadFactory,
>                               RejectedExecutionHandler handler) {
>         . . .
>     }
> ```
>
> 下面我们一一介绍这些参数的意义:
>
> * corePoolSize：表示线程池保有的最小线程数。
> * maximumPoolSize：表示线程池创建的最大线程数。
> * keepAliveTime & unit：如果一个线 程空闲了keepAliveTime & unit这么久，而且线程池的线程数大于 corePoolSize ， 那么这个空闲的线程就要被回收了。
> * workQueue：工作队列
> * threadFactory：通过这个参数你可以自定义如何创建线程，例如你可以给线程指定一 个有意义的名字。
> * handler：通过这个参数你可以自定义任务的拒绝策略。如果线程池中所有的线程都在忙碌，并且工作队列也满了（前提是工作队列是有界队列），那么此时提交任务，线程池就会拒绝接收。至于拒绝的策略，你可以通过 handler 这个参数来指定。
>
> ThreadPoolExecutor 已经提供了以下 4 种策略。
>
> *  CallerRunsPolicy：提交任务的线程自己去执行该任务。
> *  AbortPolicy：默认的拒绝策略，会 throws RejectedExecutionException。
> *  DiscardPolicy：直接丢弃任务，没有任何异常抛出。 
> * DiscardOldestPolicy：丢弃最老的任务，其实就是把最早进入工作队列的任务丢弃， 然后把新任务加入到工作队列。

# 八、 Future：如何用多线程实现最优的“烧水泡茶”程序？

>  ThreadPoolExecutor 的 void execute(Runnable command) 方法，利用这个 方法虽然可以提交任务，但是却没有办法获取任务的执行结果（execute() 方法没有返回 值）。而很多场景下，我们又都是需要获取任务的执行结果的。那 ThreadPoolExecutor 是否提供了相关功能呢？

## 如何获取任务执行结果

> Java 通过 ThreadPoolExecutor 提供的 3 个 submit() 方法和 1 个 FutureTask 工具类来支持获得任务执行结果的需求。

### ThreadPoolExecutor的 submit() 方法

> 下面我们先来介绍这 3 个 submit() 方法:
>
> ```java
> // 提交 Runnable 任务
> Future<?> submit(Runnable task);
> 
> // 提交 Callable 任务
> <T> Future<T> submit(Callable<T> task);
> 
> // 提交 Runnable 任务及结果引用
> <T> Future<T> submit(Runnable task, T result);
> ```
>
> 这三个方法的参数不尽相同，根据参数，我们来对比三个submit方法的区别：
>
> * 1、提交 Runnable 任务 submit(Runnable task) ：这个方法的参数是一个 Runnable 接口，Runnable 接口的 run() 方法是没有返回值的，所以 submit(Runnable task) 这个方法返回的 Future 仅可以用来断言任务已经结束了，类似于 Thread.join()。
> * 2、提交 Callable 任务 submit(Callable task)：这个方法的参数是一个 Callable 接口，它只有一个 call() 方法，并且这个方法是有返回值的，所以这个方法返回的 Future 对象可以通过调用其 get() 方法来获取任务的执行结果。
> * 提交 Runnable 任务及结果引用 submit(Runnable task, T result)：需要你注意的是 Runnable 接口的实现类 Task 声明了一个有参构造函数 Task(Result r) ，创建 Task 对象的时候传入了 result 对象，这样就能在类 Task 的 run() 方法中对 result 进行各种操作了。result 相当于主线程和子线程之间的桥梁，通过它主子线程可以共享数据。展示一段伪代码，看看这个方法如何使用的
>
> ```java
> ExecutorService executor = Executors.newFixedThreadPool(1);
> // 创建 Result 对象 r
> Result r = new Result();
> r.setAAA(a);
> // 提交任务
> Future<Result> future = executor.submit(new Task(r), r);
> Result fr = future.get();
> 
> // 下面等式成立
> fr === r;
> fr.getAAA() === a;
> fr.getXXX() === x
>     
>     class Task implements Runnable{
>         Result r;
>         // 通过构造函数传入 result
>         Task(Result r){
>             this.r = r;
>         }
>         void run() {
>             // 可以操作 result
>             a = r.getAAA();
>             r.setXXX(x);
>         }
>     }
> 
> ```
>
> 这三个submit方法有一个共同点，返回值类型都是Future。我们来看看Future接口提供的方法：
>
> ```java
> // 取消任务
> boolean cancel(boolean mayInterruptIfRunning);
> 
> // 判断任务是否已取消
> boolean isCancelled();
> 
> // 判断任务是否已结束
> boolean isDone();
> 
> // 获得任务执行结果
> get();
> 
> // 获得任务执行结果，支持超时
> get(long timeout, TimeUnit unit);
> ```

### FutureTask 工具类

>下面我们再来介绍 FutureTask 工具类。前面我们提到的 Future 是一个接口，而 FutureTask 是一个实实在在的工具类，这个工具类有两个构造函数，它们的参数和前面介 绍的 submit() 方法类似。
>
>```java
>FutureTask(Callable<V> callable);
>
>FutureTask(Runnable runnable, V result);
>```
>
>FutureTask 实现了 Runnable 和 Future 接 口，由于实现了 Runnable 接口，所以可以将 FutureTask 对象作为任务提交给 ThreadPoolExecutor 去执行，也可以直接被 Thread 执行；又因为实现了 Future 接口， 所以也能用来获得任务的执行结果。下面的示例代码是将 FutureTask 对象提交给 ThreadPoolExecutor 去执行。
>
>```java
>// 创建 FutureTask
>FutureTask<Integer> futureTask = new FutureTask<>(()-> 1+2);
>
>// 创建线程池
>ExecutorService es = Executors.newCachedThreadPool();
>
>// 提交 FutureTask
>es.submit(futureTask);
>
>// 获取计算结果
>Integer result = futureTask.get();
>
>```
>
>FutureTask 对象直接被 Thread 执行的示例代码如下所示。
>
>```java
>// 创建 FutureTask
>FutureTask<Integer> futureTask = new FutureTask<>(()-> 1+2);
>
>// 创建并启动线程
>Thread T1 = new Thread(futureTask);
>
>T1.start();
>
>// 获取计算结果
>Integer result = futureTask.get();
>```

## 实现最优的“烧水泡茶”程序

> 介绍了一个烧水泡茶的例子，最优的工序应该是下面这样：
>
> ![image-20221129170507696](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211291707241.png)
>
> 下面我们用程序来模拟一下这个最优工序。对于烧水泡茶这个程序，一种最优的分工方案可以是下图所示的这样：用两个线程 T1 和 T2 来完成烧水泡茶程序，T1 负责洗水壶、烧开水、泡茶这三道工序，T2 负责洗茶壶、洗茶杯、拿茶叶三道工序，其中 T1 在执行泡茶这道工序时需要等待 T2 完成拿茶叶的工序。
>
> ![image-20221129170942138](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211291709395.png)
>
> 下面的示例代码就是用这一章提到的 Future 特性来实现的。
>
> ```java
> package com.gjk.javabasis.juc.future;
> 
> import java.util.concurrent.Callable;
> import java.util.concurrent.ExecutionException;
> import java.util.concurrent.FutureTask;
> import java.util.concurrent.TimeUnit;
> 
> import org.apache.poi.ss.formula.functions.T;
> 
> /**
>  * BoilWaterForTea
>  *
>  * @author: gaojiankang
>  * @date: 2022/11/29 17:11
>  * @description:
>  */
> public class BoilWaterForTea {
>     public static void main(String[] args) throws ExecutionException, InterruptedException {
> 
>         FutureTask<String> t2 = new FutureTask<>(new SecondPartTask());
>         FutureTask<String> t1 = new FutureTask<>(new FirstPartTask(t2));
>         Thread thread2 = new Thread(t2);
>         Thread thread1 = new Thread(t1);
>         thread2.start();
>         thread1.start();
>         System.out.println(t1.get());
> 
>     }
> 
> 
> 
> 
> 
>     private static class FirstPartTask implements Callable<String>{
>         FutureTask<String> t2;
> 
>         public FirstPartTask(FutureTask<String> t2) {
>             this.t2 = t2;
>         }
> 
>         @Override
>         public String call() throws Exception {
>             System.out.println("T1:洗水壶。。。。。。");
>             TimeUnit.SECONDS.sleep(1);
> 
>             System.out.println("T1:烧开水。。。。。。");
>             TimeUnit.SECONDS.sleep(15);
>             String s = t2.get();
>             System.out.println("T1:泡茶。。。。。。");
> 
>             return "上茶" + s;
>         }
>     }
> 
>     private static class SecondPartTask implements Callable<String>{
>         @Override
>         public String call() throws Exception {
>             System.out.println("T2:洗茶壶。。。。。。");
>             TimeUnit.SECONDS.sleep(1);
> 
>             System.out.println("T2:洗茶杯。。。。。。");
>             TimeUnit.SECONDS.sleep(2);
> 
>             System.out.println("T2:拿茶叶。。。。。。");
>             TimeUnit.SECONDS.sleep(1);
> 
>             return "铁观音";
>         }
>     }
>     
> }
> 
> ```

# 九、CompletableFuture：异步编程没那么难

> 用多线程优化性能，其实不过就是将串行操作变成并行操作，而并行操作其实就是异步化。如何执行并行操作呢，我们可以通过创建多个子线程执行，那么子线程执行的操作是异步执行的。
>
> **异步化**，是并行方案得以实施的基础，更深入地讲其实就是：**利用多线程优化性能这个核心方案得以实施的基础**。Java 在 1.8 版本提供了 CompletableFuture 来支持异步编程。

## CompletableFuture 的核心优势

> 为了领略 CompletableFuture 异步编程的优势，这里我们用 CompletableFuture 重新实现前面曾提及的烧水泡茶程序。
>
> ![image-20221223111508486](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212231115341.png)
>
> ```java
> package com.gjk.javabasis.juc.completableFuture;
> 
> import java.util.concurrent.CompletableFuture;
> import java.util.concurrent.TimeUnit;
> 
> /**
>  * BoilWaterForTeaTest
>  *
>  * @author: gaojiankang
>  * @date: 2022/12/23 11:24
>  * @description:
>  */
> public class BoilWaterForTeaTest {
> 
>     public static void main(String[] args) {
> 
>         CompletableFuture<Void> t1 = CompletableFuture.runAsync(() -> {
>             System.out.println("T1:洗水壶。。。。。。");
>             sleep(1, TimeUnit.SECONDS);
> 
>             System.out.println("T1:烧开水。。。。。。");
>             sleep(15, TimeUnit.SECONDS);
>         });
> 
>         CompletableFuture<String> t2 = CompletableFuture.supplyAsync(() -> {
>             System.out.println("T2:洗茶壶。。。。。。");
>             sleep(1, TimeUnit.SECONDS);
> 
>             System.out.println("T2:洗茶杯。。。。。。");
>             sleep(2, TimeUnit.SECONDS);
> 
>             System.out.println("T2:拿茶叶。。。。。。");
>             sleep(1, TimeUnit.SECONDS);
>             return "龙井";
>         });
> 
>         CompletableFuture<String> t3 = t1.thenCombineAsync(t2, (k, v) -> {
>             System.out.println("T3:泡茶。。。。。。");
>             return "上茶" + v;
>         });
>         System.out.println(t3.join());
>     }
> 
>     public static void sleep(long timeout, TimeUnit u) {
>         try {
>             u.sleep(timeout);
>         } catch (InterruptedException e) {
>             e.printStackTrace();
>         }
>     }
> }
> 
> ```
>
> 对比一下之前实现的烧水泡茶程序和CompletableFuture实现的烧水泡茶程序，我们会发现使用CompletableFuture，无需手工维护线程，并且语义更加清晰、代码更加简练，可以让开发同学更加专注于业务逻辑。
>
> 上面的烧水泡茶代码示例中，我们用到了`CompletableFuture`的 `runAsync()`、`supplyAsync()`、`thenCombineAsync()`、`join()`方法。
>
> * runAsync()：异步执行，无返回结果。
> * supplyAsync()：异步执行，有返回结果。
> * thenCombineAsync()：异步合并，有返回结果。**在两个任务都执行完成后，把两个任务的结果合并**，如需要 '开水' + '龙井' 才能得到 '龙井茶' 。两个任务是并行执行的，它们之间并**没有先后依赖顺序**，并且两个任务中**只要有一个执行异常**，则将该异常信息作为指定任务的执行结果。
> * join()：获取异步后返回的结果。

## 如何创建CompletableFuture对象呢？

> 创建 CompletableFuture 对象主要靠下面代码中展示的4个静态方法
>
> ```java
>     /**
>      * 异步执行，默认线程池，有返回结果
>      */
>    public static <U> CompletableFuture<U> supplyAsync(Supplier<U> supplier) {
>         return asyncSupplyStage(asyncPool, supplier);
>     }
> 
>     /**
>      * 异步执行，指定线程池，有返回结果
>      */
>     public static <U> CompletableFuture<U> supplyAsync(Supplier<U> supplier,
>                                                        Executor executor) {
>         return asyncSupplyStage(screenExecutor(executor), supplier);
>     }
> 
>     /**
>      * 异步执行，默认线程池，无返回结果
>      */
>     public static CompletableFuture<Void> runAsync(Runnable runnable) {
>         return asyncRunStage(asyncPool, runnable);
>     }
> 
>     /**
>      * 异步执行，指定线程池，无返回结果
>      */
>     public static CompletableFuture<Void> runAsync(Runnable runnable,
>                                                    Executor executor) {
>         return asyncRunStage(screenExecutor(executor), runnable);
>     }
> ```
>
> **默认情况下，CompletableFuture会使用公共的ForkJoinPool线程池，这个线程池默认创建的线程数是CPU核数**（也可以通过JVM.option:-Djava.util.concurrent.ForkJoinPool.common.parallelism 来设置 ForkJoinPool 线程池的线程数）。如果所有 CompletableFuture 共享一个线程池，那么一旦有任务执行一些很慢的 I/O 操作，就会导致线程池中所有线程都阻塞在 I/O 操作上，从而造成线程饥饿，进而影响整个系统的性能。所以强烈建议要根据不同的业务类型创建不同的线程池，以避免互相干扰。
>
> 对于一个异步操作，我们需要关注两个问题：一个是异步操作什么时候结束，另一个是如何获取异步操作的执行结果。因为 CompletableFuture 类实现了 Future 接口，所以这两个问题都可与听过 Future 接口解决。
>
> 另外，CompletableFuture 类还实现了 CompletionStage 接口，这个接口在1.8版本有40个方法。

## 如何理解 CompletionStage 接口

> 站在分工的角度类比一下工作流，任务是有时序关系的，比如串行关系、并行关系、汇聚关系等。继续用烧水泡茶的例子，其中洗水壶和烧开水是串行关系、洗水壶-烧开水 和 洗茶壶-洗茶杯是并行关系，烧开水、拿茶叶和泡茶是汇聚关系。
>
> ![image-20221226113718275](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212261137997.png)
>
> ![image-20221226113725760](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212261137790.png)
>
> 并行关系就是`runAsync`和`supplyAsync`两个系列的方法，下面不再重点描述了，我们主要学习串行关系和汇聚关系。

### 1、描述串行关系

> CompletionStage 接口里面描述串行关系，主要是 `thenApply`、`thenAccept`、`thenRun `和 `thenCompose`这四个系列的接口方法。

#### thenApply系列方法

> **使用前一任务的返回值，作为当前任务的入参，串行执行，有返回值**，如果带有`Async`，则异步串行执行。值得注意的地方：如果异步线程执行慢于主线程，`thenApply`方法会由异步线程执行；如果异步线程执行快于主线程，`thenApply`方法会由主线程执行；
>
> ```java
>     public <U> CompletionStage<U> thenApply(Function<? super T,? extends U> fn);
> 
>     public <U> CompletionStage<U> thenApplyAsync(Function<? super T,? extends U> fn);
> 
>     public <U> CompletionStage<U> thenApplyAsync(Function<? super T,? extends U> fn, Executor executor);
> ```
>
> 应用示例及执行结果：
>
> ```java
>     public void testThenApply() {
>         System.out.println("main --- 开始***");
> 
>         CompletableFuture<String> completableFuture = CompletableFuture.supplyAsync(() -> {
>             String name = Thread.currentThread().getName();
>             System.out.println(name + " --- CompletableFuture.supplyAsync --- Hello World");
>             return "Hello World";
>         }).thenApplyAsync(s -> {
>             String name = Thread.currentThread().getName();
>             System.out.println(name + " --- CompletableFuture.thenApplyAsync ---" + s + "gjk");
>             return s + "gjk";
>         }, executor).thenApply(r -> {
>             String name = Thread.currentThread().getName();
>             System.out.println(name + " --- CompletableFuture.thenApply ---" + r);
>             return r;
>         });
>         System.out.println("main --- completableFuture.join前***");
>         System.out.println(completableFuture.join());
>         System.out.println("main --- 结束***");
>     }
> ```
>
> ![image-20221226153240693](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212261532057.png)

#### thenAccept系列方法

>**使用前一任务的返回值，作为当前任务的入参，串行执行，没有返回值**，如果带有`Async`，则异步串行执行。同样值得注意的地方：如果异步线程执行慢于主线程，`thenAccept`方法会由异步线程执行；如果异步线程执行快于主线程，`thenAccept`方法会由主线程执行；
>
>```java
>	public CompletionStage<Void> thenAccept(Consumer<? super T> action);
>
>  	  public CompletionStage<Void> thenAcceptAsync(Consumer<? super T> action);
>
>        public CompletionStage<Void> thenAcceptAsync(Consumer<? super T> action, Executor executor);
>```
>
>应用示例及执行结果
>
>```java
>public void testThenAccept() {
>    System.out.println("main --- 开始***");
>
>    CompletableFuture<Void> completableFuture = CompletableFuture.supplyAsync(() -> {
>        String name = Thread.currentThread().getName();
>        System.out.println(name + " --- CompletableFuture.supplyAsync --- Hello World");
>
>        return "Hello World";
>    }, executor).thenAcceptAsync(s -> {
>        String name = Thread.currentThread().getName();
>        System.out.println(name + " --- CompletableFuture.thenAcceptAsync --- Hello World" + s);
>        try {
>            Thread.sleep(3000L);
>        } catch (InterruptedException e) {
>            e.printStackTrace();
>        }
>    }).thenAccept(s ->{
>        String name = Thread.currentThread().getName();
>        System.out.println(name + " --- CompletableFuture.thenAccept --- Hello World");
>    });
>    System.out.println("main --- completableFuture.join前***");
>    completableFuture.join();
>    System.out.println("main --- 结束***");
>}
>```
>
>![image-20221226154451569](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212261544510.png)

#### thenRun系列方法

> **无参数，串行执行，无返回值**，如果带有`Async`，则异步串行执行。同样值得注意的地方：如果异步线程执行慢于主线程，`thenRun`方法会由异步线程执行；如果异步线程执行快于主线程，`thenRun`方法会由主线程执行；
>
> ```java
>     public CompletionStage<Void> thenRun(Runnable action);
> 
>     public CompletionStage<Void> thenRunAsync(Runnable action);
> 
>     public CompletionStage<Void> thenRunAsync(Runnable action, Executor executor);
> ```
>
> 应用示例及执行结果如下
>
> ```java
> public void testThenRun() {
>     System.out.println("main --- 开始***");
> 
>     CompletableFuture<Void> completableFuture = CompletableFuture.supplyAsync(() -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name + " --- CompletableFuture.supplyAsync --- Hello World");
>         return "Hello World";
>     }, executor).thenRunAsync(() -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name + " --- CompletableFuture.thenRunAsync --- Hello World");
>         try {
>             Thread.sleep(3000L);
>         } catch (InterruptedException e) {
>             e.printStackTrace();
>         }
>     }).thenRun(() ->{
>         String name = Thread.currentThread().getName();
>         System.out.println(name + " --- CompletableFuture.thenRun --- Hello World");
>     });
> 
>     System.out.println("main --- completableFuture.join前***");
>     completableFuture.join();
>     System.out.println("main --- 结束***");
> }
> ```
>
> ![image-20221226161916391](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212261619727.png)

#### thenCompose系列方法

> **使用前一任务的返回值，作为当前任务的入参，串行执行，有返回值**，如果带有`Async`，则异步串行执行。从功能看，`thenCompose`和`thenApply`相同，但是从参数看，他们之间是有区别的。
>
> * `thenApply`的参数 fn函数是对一个已完成的stage或者说CompletableFuture的的返回值进行计算、操作，相当于将CompletableFuture<T> 生成新的CompletableFuture<U>，只是将CompletableFuture的T类型转换为了U类型而已。
> * `thenCompose`的参数是 fn函数是对另一个CompletableFuture进行计算、操作，也就是说用来连接两个CompletableFuture，是生成一个新的CompletableFuture
>
> ```java
> public <U> CompletionStage<U> thenCompose(Function<? super T, ? extends CompletionStage<U>> fn);
> 
> public <U> CompletionStage<U> thenComposeAsync(Function<? super T, ? extends CompletionStage<U>> fn);
> 
> public <U> CompletionStage<U> thenComposeAsync(Function<? super T, ? extends CompletionStage<U>> fn,
>          Executor executor);
> ```
> 应用示例及执行结果
>
> ```java
> public void testThenCompose() {
>     System.out.println("main --- 开始***");
> 
>     CompletableFuture<String> completableFuture = CompletableFuture.supplyAsync(() -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name + " --- CompletableFuture.supplyAsync --- Hello World");
>         return "Hello World";
>     }, executor).thenComposeAsync(s -> CompletableFuture.supplyAsync(() -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name + " --- CompletableFuture.thenComposeAsync ---" + s + " gjk");
>         return s + " gjk";
>     })).thenCompose(s -> CompletableFuture.supplyAsync(() -> {
>         String name = Thread.currentThread().getName();
>         String s1 = s.toUpperCase();
>         System.out.println(name + " --- CompletableFuture.thenCompose ---" + s1);
>         return s1;
>     }));
> 
>     System.out.println("main --- completableFuture.join前***");
>     System.out.println(completableFuture.join());
>     System.out.println("main --- 结束***");
> }
> ```
>
> ![image-20221226171619168](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212261716807.png)

### 2、描述 AND 汇聚关系

> `CompletionStage`接口里面描述 AND 汇聚关系，主要是 `thenCombine`、`thenAcceptBoth`和`runAfterBoth`系列的接口方法。

#### thenCombine系列方法

> **在两个并行任务执行完成后，再次执行任务，需要前两个任务的结果作为入参，有返回值**，两个并行任务中只要有一个执行异常，则将该异常信息作为指定任务的执行结果。
>
> ```java
>    public <U,V> CompletionStage<V> thenCombine(CompletionStage<? extends U> other,
>         BiFunction<? super T,? super U,? extends V> fn);
> 
>     public <U,V> CompletionStage<V> thenCombineAsync(CompletionStage<? extends U> other,
>          BiFunction<? super T,? super U,? extends V> fn);
> 
>     public <U,V> CompletionStage<V> thenCombineAsync(CompletionStage<? extends U> other,
>          BiFunction<? super T,? super U,? extends V> fn, Executor executor);
> ```
>
> 应用示例及执行结果如下
>
> ```java
> public void testThenCombine(){
>     System.out.println("开始***");
> 
>     CompletableFuture<String> pot = CompletableFuture.supplyAsync(() -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name +" --- CompletableFuture.supplyAsync() --- 洗锅");
>         return "锅";
>     }, executor);
> 
>     CompletableFuture<String> meter = CompletableFuture.supplyAsync(() -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name +" --- CompletableFuture.runAsync() --- 洗米");
>         return "米";
>     },executor);
> 
>     CompletableFuture<String> rice1 = meter.thenCombine(pot, (v1, v2) -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name +" --- pot,Meter --- 获取'" + v2 + "'和'" + v1 + "'后开始煮饭");
>         return "白米饭 + thenCombine";
>     });
> 
>     CompletableFuture<String> rice2 = meter.thenCombineAsync(pot, (v1, v2) -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name +" --- pot,Meter --- 获取'" + v2 + "'和'" + v1 + "'后开始煮饭");
>         return "白米饭 + thenCombineAsync";
>     });
> 
>     CompletableFuture<String> rice3 = meter.thenCombineAsync(pot, (v1, v2) -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name +" --- pot,Meter --- 获取'" + v2 + "'和'" + v1 + "'后开始煮饭");
>         return "白米饭 + thenCombineAsync + executor";
>     },executor);
>     List<String> collect = Stream.of(rice1, rice2, rice3).map(CompletableFuture::join).collect(Collectors.toList());
>     System.out.println("result: " + JSON.toJSONString(collect));
>     System.out.println("结束***");
> }
> ```
>
> ![image-20221226175252117](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212261752285.png)

#### thenAcceptBoth系列方法

> **在两个并行任务执行完成后，再次执行任务，需要前两个任务的结果作为入参，无返回值**。
>
> ```java
>     public <U> CompletionStage<Void> thenAcceptBoth
>         (CompletionStage<? extends U> other,
>          BiConsumer<? super T, ? super U> action);
> 
> public <U> CompletionStage<Void> thenAcceptBothAsync
>     (CompletionStage<? extends U> other,
>      BiConsumer<? super T, ? super U> action);
> 
> public <U> CompletionStage<Void> thenAcceptBothAsync
>     (CompletionStage<? extends U> other,
>      BiConsumer<? super T, ? super U> action,
>      Executor executor);
> ```
> 应用示例及执行结果
>
> ```java
>     public void testThenAcceptBoth(){
>         System.out.println("开始***");
> 
>         CompletableFuture<String> pot = CompletableFuture.supplyAsync(() -> {
>             String name = Thread.currentThread().getName();
>             System.out.println(name +" --- CompletableFuture.supplyAsync() --- 洗锅");
>             return "锅";
>         }, executor);
> 
>         CompletableFuture<String> meter = CompletableFuture.supplyAsync(() -> {
>             String name = Thread.currentThread().getName();
>             System.out.println(name +" --- CompletableFuture.runAsync() --- 洗米");
>             return "米";
>         },executor);
> 
>         CompletableFuture<Void> rice1 = meter.thenAcceptBoth(pot, (v1, v2) -> {
>             String name = Thread.currentThread().getName();
>             System.out.println(name +" --- pot,Meter --- 获取'" + v2 + "'和'" + v1 + "'后开始煮饭");
>         });
> 
>         CompletableFuture<Void> rice2 = meter.thenAcceptBothAsync(pot, (v1, v2) -> {
>             String name = Thread.currentThread().getName();
>             System.out.println(name +" --- pot,Meter --- 获取'" + v2 + "'和'" + v1 + "'后开始煮饭");
>         });
> 
>         CompletableFuture<Void> rice3 = meter.thenAcceptBothAsync(pot, (v1, v2) -> {
>             String name = Thread.currentThread().getName();
>             System.out.println(name +" executor --- pot,Meter --- 获取'" + v2 + "'和'" + v1 + "'后开始煮饭");
>         },executor);
>         CompletableFuture.allOf(rice1, rice2, rice3).join();
>         System.out.println("结束***");
>     }
> ```
>
> ![image-20221227113341228](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212271133356.png)

#### runAfterBoth系列方法

> **在两个并行任务执行完成后，再次执行任务，无参数，无返回值**。
>
> ```java
>     public CompletionStage<Void> runAfterBoth(CompletionStage<?> other,
>                                           Runnable action);
> 
>     public CompletionStage<Void> runAfterBothAsync(CompletionStage<?> other,
>                                                    Runnable action);
> 
>     public CompletionStage<Void> runAfterBothAsync(CompletionStage<?> other,
>                                                    Runnable action,
>                                                    Executor executor);
> ```
>
> 应用示例及执行结果
>
> ```java
> public void testRunAfterBoth(){
>     System.out.println("开始***");
> 
>     CompletableFuture<String> pot = CompletableFuture.supplyAsync(() -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name +" --- CompletableFuture.supplyAsync() --- 洗锅");
>         return "锅";
>     }, executor);
> 
>     CompletableFuture<String> meter = CompletableFuture.supplyAsync(() -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name +" --- CompletableFuture.runAsync() --- 洗米");
>         return "米";
>     },executor);
> 
>     CompletableFuture<Void> completableFuture1 = meter.runAfterBoth(pot, () -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name + " --- CompletableFuture.runAfterBoth --- 无参数，无返回值");
>     });
> 
>     CompletableFuture<Void> completableFuture2 = meter.runAfterBothAsync(pot, () -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name + " --- CompletableFuture.runAfterBothAsync --- 无参数，无返回值");
>     });
> 
>     CompletableFuture<Void> completableFuture3 = meter.runAfterBothAsync(pot, () -> {
>         String name = Thread.currentThread().getName();
>         System.out.println(name + " --- CompletableFuture.runAfterBothAsync + executor --- 无参数，无返回值");
>     }, executor);
>     CompletableFuture.allOf(completableFuture1, completableFuture2, completableFuture3).join();
>     System.out.println("结束***");
> }
> ```
>
> ![image-20221227120017005](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212271200091.png)

### 3、描述 OR 汇聚关系

> CompletionStage 接口里面描述 OR 汇聚关系，主要是 applyToEither、acceptEither 和 runAfterEither 系列的接口。

#### applyToEither系列方法

> **两个任务中最先完成的任务结果作为入参，执行新任务，有返回值**。
>
> ```java
> public <U> CompletionStage<U> applyToEither
>     (CompletionStage<? extends T> other,
>      Function<? super T, U> fn);
> 
>  public <U> CompletionStage<U> applyToEitherAsync
>      (CompletionStage<? extends T> other,
>       Function<? super T, U> fn);
> 
>  public <U> CompletionStage<U> applyToEitherAsync
>      (CompletionStage<? extends T> other,
>       Function<? super T, U> fn,
>       Executor executor);
> ```
>
> 应用示例及执行结果
>
> ```java
> public void testApplyToEither() {
>  System.out.println("开始***");
>  System.out.println("张三等电梯上楼");
>  CompletableFuture<String> completableFuture = CompletableFuture.supplyAsync(() -> {
>      String name = Thread.currentThread().getName();
>      System.out.println(name + " --- CompletableFuture.supplyAsync() --- 1号电梯下行中");
>      try {
>          TimeUnit.SECONDS.sleep(5L);
>      } catch (InterruptedException e) {
>          e.printStackTrace();
>      }
>      return "1号电梯";
>  }, executor).applyToEitherAsync(CompletableFuture.supplyAsync(() -> {
>      String name = Thread.currentThread().getName();
>      System.out.println(name + " --- CompletableFuture.supplyAsync() --- 2号电梯下行中");
>      try {
>          TimeUnit.SECONDS.sleep(3L);
>      } catch (InterruptedException e) {
>          e.printStackTrace();
>      }
>      return "2号电梯";
>  }, executor), result -> {
>      String name = Thread.currentThread().getName();
>      System.out.println(name + " --- CompletableFuture.applyToEitherAsync() --- " + result + "到达");
>      return "张三上了" + result;
>  }, executor);
> 
>  System.out.println(completableFuture.join());
>  System.out.println("结束***");
> }
> ```
>
> ![image-20221227161137676](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212271611985.png)

#### acceptEither系列方法

> **两个任务中最先完成的任务结果作为入参，执行新任务，无返回值**。
>
> ```java
> public <U> CompletionStage<U> applyToEither
>     (CompletionStage<? extends T> other,
>      Function<? super T, U> fn);
> 
>  public <U> CompletionStage<U> applyToEitherAsync
>      (CompletionStage<? extends T> other,
>       Function<? super T, U> fn);
> 
>  public <U> CompletionStage<U> applyToEitherAsync
>      (CompletionStage<? extends T> other,
>       Function<? super T, U> fn,
>       Executor executor);
> ```
>
> ```java
> public CompletionStage<Void> acceptEither
>     (CompletionStage<? extends T> other,
>      Consumer<? super T> action);
> 
>  public CompletionStage<Void> acceptEitherAsync
>      (CompletionStage<? extends T> other,
>       Consumer<? super T> action);
> 
>  public CompletionStage<Void> acceptEitherAsync
>      (CompletionStage<? extends T> other,
>       Consumer<? super T> action,
>       Executor executor);
> ```
>
> 应用示例及执行结果
>
> ```java
> public void testAcceptEither() {
>  System.out.println("开始***");
>  System.out.println("张三等电梯上楼");
>  CompletableFuture<Void> completableFuture = CompletableFuture.supplyAsync(() -> {
>      String name = Thread.currentThread().getName();
>      System.out.println(name + " --- CompletableFuture.supplyAsync() --- 1号电梯下行中");
>      try {
>          TimeUnit.SECONDS.sleep(5L);
>      } catch (InterruptedException e) {
>          e.printStackTrace();
>      }
>      return "1号电梯";
>  }, executor).acceptEitherAsync(CompletableFuture.supplyAsync(() -> {
>      String name = Thread.currentThread().getName();
>      System.out.println(name + " --- CompletableFuture.supplyAsync() --- 2号电梯下行中");
>      try {
>          TimeUnit.SECONDS.sleep(3L);
>      } catch (InterruptedException e) {
>          e.printStackTrace();
>      }
>      return "2号电梯";
>  }, executor), result -> {
>      String name = Thread.currentThread().getName();
>      System.out.println(name + " --- CompletableFuture.applyToEitherAsync() --- " + result + "到达");
>      System.out.println(name + " --- CompletableFuture.applyToEitherAsync() --- 张三进入" + result);
>  }, executor);
> 
>  completableFuture.join();
>  System.out.println("结束***");
> }
> ```
>
> ![image-20221227162228437](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212271622199.png)

#### runAfterEither系列方法

> **两个任务都在进行，只要其中一个任务做完，新任务就开始执行，无入参，无返回值**。
>
> ```java
> public CompletionStage<Void> runAfterEither(CompletionStage<?> other,
>                                          Runnable action);
> 
>  public CompletionStage<Void> runAfterEitherAsync
>      (CompletionStage<?> other,
>       Runnable action);
> 
>  public CompletionStage<Void> runAfterEitherAsync
>      (CompletionStage<?> other,
>       Runnable action,
>       Executor executor);
> ```
>
> 应用示例及执行结果
>
> ```java
> public void testRunAfterEither() {
>  System.out.println("开始***");
> 
>  System.out.println("小明和小黄分别在家做饭，小红等着吃饭！！！");
>  CompletableFuture<Void> completableFuture = CompletableFuture.supplyAsync(() -> {
>      String name = Thread.currentThread().getName();
>      System.out.println(name + " --- CompletableFuture.runAsync() --- 小明正在做饭");
>      try {
>          TimeUnit.SECONDS.sleep(5L);
>      } catch (InterruptedException e) {
>          e.printStackTrace();
>      }
>      System.out.println(name + " --- CompletableFuture.runAsync() --- 小明饭做好了");
>      return "小明做的饭好了";
>  }, executor).runAfterEitherAsync(CompletableFuture.supplyAsync(() -> {
>      String name = Thread.currentThread().getName();
>      System.out.println(name + " --- CompletableFuture.runAsync() --- 小黄正在做饭");
>      try {
>          TimeUnit.SECONDS.sleep(10L);
>      } catch (InterruptedException e) {
>          e.printStackTrace();
>      }
>      System.out.println(name + " --- CompletableFuture.runAsync() --- 小黄饭做好了");
>      return "小黄做的饭好了";
>  }, executor), () -> {
>      String name = Thread.currentThread().getName();
>      System.out.println(name + " --- CompletableFuture.applyToEitherAsync() --- 小红吃饭了");
>  }, executor);
> 
>  completableFuture.join();
>  System.out.println("结束***");
> }
> ```
>
> ![image-20221227165142273](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212271651691.png)

### 4、异常处理

> 上面我们提到的方法，他们的参数都是都不允许抛出可检查异常， 但是却无法限制它们抛出运行时异常。CompletionStage 接口给我们提供的方案非常简单，提供了`exceptionally`、`whenComplete`、`handle`接口方法处理异常，使用这些方法进行异常处理和串行操作是一样的，都支持链式编程方式。

#### exceptionally方法

> **exceptionally() 的使用非常类似于 try{}catch{}中的 catch{}，如果链式前段出现异常，`exceptionally()`会捕获异常，以异常为参数，并且有返回值**。
>
> ```java
> public CompletionStage<T> exceptionally(Function<Throwable, ? extends T> fn);
> ```
>
> 应用示例及执行结果
>
> ```java
> public void testExceptionally(){
>     CompletableFuture<Integer> completableFuture = CompletableFuture.supplyAsync(() -> 7 / 0)
>             .thenApply(r -> r * 10)
>             //异常被exceptionally捕获，并且输出 0 ，等同于try-catch
>             .exceptionally(e -> 0);
>     System.out.println(completableFuture.join());
> ```
>
> ![image-20230104164937577](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202301041649574.png)

#### whenComplete系列方法

> **whenComplete()方法的作用类似于try-finally中的finally{}使用，以前段链式的返回值和可能出现的异常为参数，并且没有返回值**。
>
> ```java
>    public CompletionStage<T> whenComplete
>     (BiConsumer<? super T, ? super Throwable> action);
> 
>     public CompletionStage<T> whenCompleteAsync
>         (BiConsumer<? super T, ? super Throwable> action);
> 
>     public CompletionStage<T> whenCompleteAsync
>         (BiConsumer<? super T, ? super Throwable> action,
>          Executor executor);
> ```
>
> 应用示例及执行结果：
>
> ```java
> public void testWhenComplete(){
>     CompletableFuture<Integer> completableFuture = CompletableFuture.supplyAsync(() -> 7 / 0)
>                     .whenComplete((x,y) -> {
>                         if(y != null){
>                             System.out.println("error:" + y.getMessage() );
>                         }
>                     }).exceptionally(e -> 0);
> 
>     System.out.println(completableFuture.join());
> }
> ```
>
> ![image-20230105111539350](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202301051115952.png)

#### handler系列方法

> **handler方法的作用和whenComplete方法差不多，都类似于finally。不同的在于handler是具有返回值，而whenComplete不具有返回值**。
>
> ```java
>    public <U> CompletionStage<U> handle
>     (BiFunction<? super T, Throwable, ? extends U> fn);
> 
>     public <U> CompletionStage<U> handleAsync
>         (BiFunction<? super T, Throwable, ? extends U> fn);
> 
>     public <U> CompletionStage<U> handleAsync
>         (BiFunction<? super T, Throwable, ? extends U> fn,
>          Executor executor);
> ```
>
> 应用示例及执行结果：
>
> ```java
> public void testHandle(){
>     CompletableFuture<Integer> completableFuture = CompletableFuture.supplyAsync(() -> 7 / 0)
>             .handle((x,y) -> {
>                 if(y != null){
>                     System.out.println("error:" + y.getMessage() );
>                     return 0;
>                 }
>                 return x;
>             });
> 
>     System.out.println(completableFuture.join());
> }
> ```
>
> ![image-20230105114418219](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202301051144849.png)

# 十、CompletionService：如何批量执行异步任务？

> 如何批量执行异步任务呢？举个场景：班长收作业，小红、小明、小朋抓住最后的时间在补作业。
>
> 首先我们通过`ExecutorService + Future`去实现这个过程，代码如下：
>
> ```java
> private final ExecutorService executor = new ThreadPoolExecutor(
>         Runtime.getRuntime().availableProcessors(),
>         Runtime.getRuntime().availableProcessors() * 2,
>         30L,
>         TimeUnit.SECONDS,
>         new LinkedBlockingQueue<>(50),
>         new ThreadFactoryBuilder().setNamePrefix("ExecutorServiceTest-").build(),
>         new ThreadPoolExecutor.CallerRunsPolicy());
> 
> 
> public void collectHomework(){
>     Future<String> future1 = executor.submit(() -> {
>         String name = Thread.currentThread().getName();
>         TimeUnit.SECONDS.sleep(10);
>         System.out.println(name + "小红交作业");
>         return "小红的作业";
>     });
> 
>     Future<String> future2 = executor.submit(() -> {
>         String name = Thread.currentThread().getName();
>         TimeUnit.SECONDS.sleep(3);
>         System.out.println(name +"小明交作业");
>         return "小明的作业";
>     });
> 
>     Future<String> future3 = executor.submit(() -> {
>         String name = Thread.currentThread().getName();
>         TimeUnit.SECONDS.sleep(1);
>         System.out.println(name +"小朋交作业");
>         return "小朋的作业";
>     });
> 
>     try {
>         System.out.println("收" + future1.get());
>         System.out.println("收" + future2.get());
>         System.out.println("收" + future3.get());
>     } catch (InterruptedException e) {
>         e.printStackTrace();
>     } catch (ExecutionException e) {
>         e.printStackTrace();
>     }
> 
> }
> ```
>
> 执行结果如下：
>
> ![image-20230105170558753](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202301051706309.png)
>
> 小红写作业用了10s，小明写作业用了3s，小朋写作业用了1s，但是班长收作业永远需要等待小红写好作业上交，才能收小明的作业，小朋也有着同样的问题。有没有什么办法可以让班长不用等小红，谁写好就收谁的作业呢？
>
> 如果我们将小红、小明、小朋写好作业后，自己交到讲台上，然后班长只负责从讲台上收作业，就可以完美解决这个问题。讲台就好比一个队列，异步线程执行完后，将结果丢入队列，主线程只需要从队列中获取执行结果。这样，执行快的异步线程的返回结果，可以优先得到处理。
>
>  Java SDK 并发包里已经提供了设计精良的 CompletionService。利用 CompletionService 不仅可以帮我们解决这类问题，而且还能让代码更简练。
>
> **CompletionService 的实现原理也是内部维护了一个阻塞队列，当任务执行结束就把任务的执行结果 Future 对象加入到阻塞队列中**。
>
> CompletionService 接口的实现类是 ExecutorCompletionService，这个实现类的构造方法有两个，分别是：
>
> ```java
> public ExecutorCompletionService(Executor executor) {
>     if (executor == null)
>         throw new NullPointerException();
>     this.executor = executor;
>     this.aes = (executor instanceof AbstractExecutorService) ?
>         (AbstractExecutorService) executor : null;
>     this.completionQueue = new LinkedBlockingQueue<Future<V>>();
> }
> 
>     public ExecutorCompletionService(Executor executor,
>                                      BlockingQueue<Future<V>> completionQueue) {
>         if (executor == null || completionQueue == null)
>             throw new NullPointerException();
>         this.executor = executor;
>         this.aes = (executor instanceof AbstractExecutorService) ?
>             (AbstractExecutorService) executor : null;
>         this.completionQueue = completionQueue;
>     }
> ```
>
> 这两个构造方法都需要传入一个线程池，如果不指定 completionQueue，那么默认会使用无界的 LinkedBlockingQueue。任务执行结果的 Future 对象就是加入到 completionQueue 中。
>
> 下面我们尝试用`CompletionService `来解决收作业的问题：
>
> ```java
> /**
>  * CompletionService实现
>  */
> public void collectHomework2() {
>     CompletionService<String> completionService = new ExecutorCompletionService<>(executor);
>     completionService.submit(() -> {
>         String name = Thread.currentThread().getName();
>         TimeUnit.SECONDS.sleep(10);
>         System.out.println(name + "小红交作业");
>         return "小红的作业";
>     });
> 
>     completionService.submit(() -> {
>         String name = Thread.currentThread().getName();
>         TimeUnit.SECONDS.sleep(3);
>         System.out.println(name +"小明交作业");
>         return "小明的作业";
>     });
> 
>     completionService.submit(() -> {
>         String name = Thread.currentThread().getName();
>         TimeUnit.SECONDS.sleep(1);
>         System.out.println(name +"小朋交作业");
>         return "小朋的作业";
>     });
> 
>     try {
>         System.out.println("收" + completionService.take().get());
>         System.out.println("收" + completionService.take().get());
>         System.out.println("收" + completionService.take().get());
>         System.out.println("作业收完，班长将作业送到老师办公室");
>     } catch (InterruptedException | ExecutionException e) {
>         e.printStackTrace();
>     }
> }
> ```
>
> 执行结果如下：
>
> ![image-20230105175044388](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202301051750736.png)
>
> 多个异步任务执行并且有返回结果，我们不在需要等待处理。谁先执行完，就先处理谁。

# 十一、Fork/Join

> 对于简单的并行任务，你可以通过“线程池 +Future”的方案来解决；如果任务之间有聚合关系，无论是 AND 聚合还是 OR 聚合，都可以通过 CompletableFuture 来解决；而批量的并行任务，则可以通过 CompletionService 来解决。
>
> ![image-20230113134935881](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202301131349267.png)
>
> 上面提到的简单并行、聚合、批量并行这三种任务模型，基本上能够覆盖日常工作中的并发场景了，但还是不够全面，因为还有一种“分治”的任务模型没有覆盖到。**分治，顾名思义，即分而治之，是一种解决复杂问题的思维方法和模式**；具体来讲，指的是把一个复杂的问题分解成多个相似的子问题，然后再把子问题分解成更小的子问题，直到子问题简单到可以直接求解。
>
> 分治思想在很多领域都有广泛的应用，例如算法领域有分治算法（归并排序、快速排序都属 于分治算法，二分法查找也是一种分治算法）；大数据领域知名的计算框架 MapReduce 背后的思想也是分治。既然分治这种任务模型如此普遍，那 Java 显然也需要支持，Java 并发包里提供了一种叫做 Fork/Join 的并行计算框架，就是用来支持分治这种任务模型的。

## 分治任务模型

> 分治任务模型可分为两个阶段：一个阶段是任务分解，也就是将任务迭代分解为子任务，直至子任务可以直接计算出结果；另一个阶段是结构合并，即逐层合并子任务的执行结果，直至获得最终结果。下图是一个简化的分治任务模型图：
>
> ![image-20230113160053375](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202301131600668.png)
>
> 在这个分治任务模型里，任务和分解后的子任务具有相似性，所以任务和子任务的算法是相同的，只是数据规模是不同的。这种问题，我们可以通过递归算法解决。

## Fork/Join的使用

> `Fork/Join`是一个并行计算框架，主要就是用来支持分治任务模型的。在这个计算框架里的**Fork 对应的是分治任务模型里的任务分解**，**Join 对应的是结果合并**。`Fork/Join`计算框架主要包含两部分，一部分是**分治任务的线程池 ForkJoinPool**，另一部分是**分治任务 ForkJoinTask**。这两部分的关系类似于  `ThreadPoolExecutor`和`Runnable`的关系，可以理解成提交任务到线程池，只不过分治任务有自己独特任务类型`ForkJoinTask`。
>
> `ForkJoinTask`是一个抽象类，它的方法有很多，最核心的是`fork()`方法和`join()`方法。`fork()`方法会异步执行一个子任务，而`join()`方法则会阻塞当前线程来等待子任务的执行结果。
>
> `ForkJoinTask`有两个子类——`RecursiveAction`和`ResursiveTask`,由名称我们可以知道，他们都是用递归的方式来处理分治任务。这两个子类都定义了抽象方法`compute()`,但是它们是有区别的，`RecursiveAction`定义的`compute()`没有返回值，而`RecursiveTask`定义的`compute()`方法是有返回值的。
>
> 接下来我们就来实现一下，看看如何用 Fork/Join 这个并行计算框架计算斐波那契数列：
>
> ```java
> package com.gjk.javabasis.juc.forkJoinPool;
> 
> import java.util.concurrent.ForkJoinPool;
> import java.util.concurrent.RecursiveTask;
> 
> /**
>  * FibonacciTest
>  *
>  * @author: gaojiankang
>  * @date: 2023/1/6 9:59
>  * @description:
>  */
> public class FibonacciTest {
> 
> 
>     public static void main(String[] args) {
>         // 创建分治任务线程池
>         ForkJoinPool fjp = new ForkJoinPool(4);
>         // 创建分治任务
>         Fibonacci fib = new Fibonacci(2);
>         // 启动分治任务
>         Integer result = fjp.invoke(fib);
>         // 输出结果
>         System.out.println(result);
>     }
> 
>     static class Fibonacci extends RecursiveTask<Integer>{
> 
>         final int n;
> 
>         Fibonacci(int n) {
>             this.n = n;
>         }
> 
>         @Override
>         protected Integer compute() {
>             if(n <=1){
>                 return n;
>             }
>             Fibonacci fibonacci1 = new Fibonacci(n - 1);
>             //创建子任务
>             fibonacci1.fork();
>             Fibonacci fibonacci2 = new Fibonacci(n - 2);
>             //等待子任务结果，合并结果
>             return fibonacci2.compute() + fibonacci1.join();
> 
>         }
>     }
> }
> ```

## Fork/Join工作原理

> ThreadPoolExecutor 本质上是一个生产者 - 消费者模式的实现，内部有一个任务队列，这个任务队列是生产者和消费者通信的媒介； ThreadPoolExecutor 可以有多个工作线程，但是这些工作线程都共享一个任务队列。
>
> ForkJoinPool 本质上也是一个生产者 - 消费者模式的实现，但是它内部有多个任务队列。当我们通过 ForJoinPool 的 invoke() 或者 submit() 方法提交任务时，ForkJoinPool 会根据一定的路由规则把任务提交到一个任务队列中，如果任务在执行过程中会创建出子任务，那么子任务会提交到工作线程对应的任务队列中。
>
> ForkJoinPool 支持一种叫“任务窃取”的机制，如果工作线程空闲了，那么它可以窃取其他工作任务队列里的任务。例如下图，线程T2对应的任务队列已经为空了，它可以窃取线程T1对应的任务队列中的任务，如此一来，所有工作线程都不会闲下来。
>
> ![image-20230203105946760](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202302031059929.png)
>
> ForkJoinPool 中的任务队列采用的是双端队列，工作线程正常获取任和“窃取任务”分别是从任务队列不同的端消费，这样能避免很多不必要的数据竞争。
>
> Java 1.8 提供的 Stream API 里面并行流也是以 ForkJoinPool 为基础的。不过需要你注意的是，默认情况下所有的并行流计算都共享一个 ForkJoinPool，这个共享的 ForkJoinPool 默认的线程数是 CPU 的核数；如果所有的并行流计算都是 CPU 密集型计算 的话，完全没有问题，但是如果存在 I/O 密集型的并行流算，那么很可能会因为一个很慢的 I/O 计算而拖慢整个系统的性能。所以建议用不同的 ForkJoinPool 执行不同类型的计算任务。
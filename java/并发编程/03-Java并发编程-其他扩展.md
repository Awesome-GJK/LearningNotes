# 一、不变性（Immutability）模式

> "多个线程同时读写同一个共享变量存在并发问题"，这是的必要条件之一是读写，如果只是读，而没有写，是没有并发问题的。
>
> 解决并发问题，最简单的方法就是让共享变量只有读操作，而没有写操作。刚好有一个解决此类问题的并发设计模式：**不变性（Immutability）模式**。所谓不变性，简单来讲，就是**对象一旦被创建之后，状态就不再发生变化**。

## 快速实现具备不可变性的类

>如何实现一个具备不可变性的类？我们可以**将一个类所有的属性都设置成`final`，并且只允许存在只读方法**，那么这个类基本上就具备不可变性了。**更严格的做法是这个类本身是`final`的，也就是不允许继承**。因为子类可以覆盖父类的方法，有可能改变不可变性，所以更加推荐使用这种更严格的做法。 
>
>Java SDK 里面很多类都具备不可变性，例如String、Long、Integer、Double 等基础类型的包装类都具备不可变性。查看这些类的源码，我们会发现：**类和属性都是final的，所有方法均是只读的**。
>
>你可能会疑惑，Java 中 String 方法中有字符串替换`replace()`操作，这个方法是写操作，并不是只读操作啊？那我们看看 Java 1.8 SDK 中 String的关键源码：
>
>```java
>public final class String
>    implements java.io.Serializable, Comparable<String>, CharSequence {
>    /** final修饰的属性 */
>    private final char value[];
>    
>    /**
>       * 字符串拼接 concat()
>       */
>    public String concat(String str) {
>        if (str.isEmpty()) {
>            return this;
>        }
>        int len = value.length;
>        int otherLen = str.length();
>        char buf[] = Arrays.copyOf(value, len + otherLen);
>        str.getChars(buf, len);
>        // 返回新的String对象
>        return new String(buf, true);
>    }
>    
>    /**
>       * 字符串替换 replace()
>       */
>    public String replace(char oldChar, char newChar) {
>        if (oldChar != newChar) {
>            int len = value.length;
>            int i = -1;
>            char[] val = value; /* avoid getfield opcode */
>
>            while (++i < len) {
>                if (val[i] == oldChar) {
>                    break;
>                }
>            }
>            if (i < len) {
>                char buf[] = new char[len];
>                for (int j = 0; j < i; j++) {
>                    buf[j] = val[j];
>                }
>                while (i < len) {
>                    char c = val[i];
>                    buf[i] = (c == oldChar) ? newChar : c;
>                    i++;
>                }
>                // 返回新的String对象
>                return new String(buf, true);
>            }
>        }
>        return this;
>    }
>
>```
>
>我们先后列出了`value[]`属性、`concat()`方法、`replace()`方法，我们可以看到 String 这个类以及它的属性`value[]`都是`final`的；而`concat()`方法、`replace()`方法的实现，的确没有修改`value[]`，而是返回新生成的 String 对象。
>
>通过分析 String 的源码我们知道，如果让我们创建一个具备不可变性的类，并且需要提供修改方法，我们可以模仿 String 的实现，创建并返回一个新的不可变对象。

## 利用享元模式避免创建重复对象

> 所有的修改操作都创建一个新的不可变对象，你可能会有这种担心：是不是创建的对象太多了，有点太浪费内存呢？如何解决呢？
>
> **利用享元模式（Flyweight Pattern）可以减少创建对象的数量，从而减少内存占用**。Java 语言里面 Long、Integer、Short、Byte 等这些基本数据类型的包装类都用到了享元模式。
>
> **享元模式本质上其实就是一个对象池，利用享元模式创建对象的逻辑也很简单：创建之前，首先去对象池里看看是不是存在；如果已经存在，就利用对象池里的对象；如果不存在，就会新创建一个对象，并且把这个新创建出来的对象放进对象池里**。
>
> 下面我们就以 Long 这个类作为例子，看看它是如何利用享元模式来优化对象的创建的。
>
> Long 这个类并没有照搬享元模式，Long 内部维护了一个静态的对象池，仅缓存了[-128,127]之间的数字（如下图所示），这个对象池在JVM启动时就创建好了。之所以采用这样的设计，是因为 Long 对象的状态有 2^64 种，实在太多，不宜全部缓存，而[-128,127]之间的数字利用率最高，并且`valueOf()`方法就用到了`LongCache`缓存。
>
> ```java
> public final class Long extends Number implements Comparable<Long> {
>     
>     /**
>        * valueOf方法
>        */
>     public static Long valueOf(long l) {
>         final int offset = 128;
>         if (l >= -128 && l <= 127) { 
>             // 使用 cache
>             return LongCache.cache[(int)l + offset];
>         }
>         return new Long(l);
>     }
>     
>      /**
>        * 静态的对象池
>        */
>     private static class LongCache {
>         private LongCache(){}
> 
>         static final Long cache[] = new Long[-(-128) + 127 + 1];
>         
>         // 初始化对象池中的数据
>         static {
>             for(int i = 0; i < cache.length; i++)
>                 cache[i] = new Long(i - 128);
>         }
>     }
> }
> ```
>
> **基本上所有的基础类型的包装类都不适合做锁，因为它们内部用到了享元模式，这会导致看上去私有的锁，其实是共有的。**

## 使用 Immutability 模式的注意事项

> 在使用 Immutability 模式的时候，需要注意以下两点：
>
> * 对象的所有属性都是 final 的，并不能保证不可变性；
> * 不可变对象也需要正确发布。
>
> 在Java语言中，final修饰的属性一旦被赋值，就不可以再修改，但是如果属性的类型是普通对象，那么这个普通对象的属性是可以被修改的。例如下面的代码，Bar的属性foo虽然是final的，但是依然可以通过setAge()方法来设置foo的属性age。所以**在使用Immutability模式的时候一定要确认保持不变性的边界在哪里，是否要求属性对象也具备不可变性**。
>
> ```java
> class Foo{
>     int age=0;
>     int name="abc";
> }
> final class Bar {
>     final Foo foo;
>     void setAge(int a){
>         foo.age=a;
>     }
> }
> 
> ```
>
> 下面我们再看看如何正确的发布不可变对象。不可变对象虽然是线程安全的，但是并不意味着引用这些不可变对象就是线程安全的。例如在下面的代码中，Foo具备不可变性，线程安全，但是类Bar并不是线程安全的，类Bar中持有对Foo的引用foo，对foo这个引用的修改在多线程中并不能保证可见性和原子性。
>
> ```java
> //Foo 线程安全
> final class Foo{
>     final int age=0;
>     final int name="abc";
> }
> //Bar 线程不安全
> class Bar {
>     Foo foo;
>     void setFoo(Foo f){
>         this.foo=f;
>     }
> }
> 
> ```
>
> 如果程序仅需要foo保持可见性，无需保证原子性，那么可以将foo
>
> 声明为`volatile`变量，这样就能保证可见性。如果程序需要保证原子性，那么我们可以通过原子类来实现。
>
> ```java
> public class SafeWM {
>     class WMRange{
>         final int upper;
>         final int lower;
>         WMRange(int upper,int lower){
>             // 省略构造函数实现
>         }
>     }
>     final AtomicReference<WMRange>
>         rf = new AtomicReference<>(
>         new WMRange(0,0)
>     );
>     // 设置库存上限
>     void setUpper(int v){
>         while(true){
>             WMRange or = rf.get();
>             // 检查参数合法性
>             if(v < or.lower){
>                 throw new IllegalArgumentException();
>             }
>             WMRange nr = new
>                 WMRange(v, or.lower);
>             if(rf.compareAndSet(or, nr)){
>                 return;
>             }
>         }
>     }
> }
> ```

# 二、Copy-on-Write模式

> 在不变性模式中，我们知道String类的修改操作并没有直接更改原字符串，而是重新创建了一个新字符串，这种方式本质上就是一种`Copy-on-Write`方法。
>
> 不可变对象的写操作往往都是使用`Copy-on-Write`方法解决的，当然`Copy-on-Write`的应用领域并不局限于`Immutability`模式，我们来看看`Copy-on-Write`还被应用在哪些领域吧

## Copy-on-Write模式的应用领域

> 在JDK中，我们知道有`CopyOnWriteArrayList`和`CopyOnWriteArraySet`这两个容器，他们背后的设计思想就是`Copy-on-Write`；通过 Copy-on-Write 这两个容器实现的读操作是无锁的，由于无锁，所以将读操作的性能发挥到了极致。CopyOnWriteArrayList 和 CopyOnWriteArraySet 使用`Copy-on-Write`的目的都是`以空间换时间`。这两个 Copy-on-Write 容器在修改的时候会复制整个数组，所以如果容器经常被修改或者这个数组本身就非常大的时候，是不建议使用的。反之，如果是修改非常少、数组数量也不大，并且对读性能要求苛刻的场景，使用 Copy-on-Write 容器效果就非常好了。
>
> 在操作系统领域中，创建进程会用到`fork()`，传统的`fork()`函数会创建父进程的一个完整副本，这边也是用到的`Copy-on-Write`设计思想。
>
> 除了上面所说的领域外，我们还可以在很多其他领域看到`Copy-on-Write`的身影：Docker 容器镜像的设计是 Copy-on-Write、分布式源码管理系统 Git 背后 的设计思想都有 Copy-on-Write

# 三、 线程本地存储模式

> 我们知道多个线程同时读写同一共享变量存在并发问题，为此我们可以突破共享变量，没有共享变量就不会有并发问题，可以使用局部变量。正所谓没有共享，就没有伤害，本质上就是避免共享，除了局部变量，Java语言提供的线程本地存储（ThreadLocal）就能做到。

## ThreadLocal 的使用方法

> ```java
> public class ThreadLocalDemo {
> 
>     private ThreadLocal<Integer> intThreadLocal = ThreadLocal.withInitial(() -> 0);
> 
>     private ThreadLocal<String> strThreadLocal = ThreadLocal.withInitial(() -> "Hello");
> 
>     private final Semaphore semaphore = new Semaphore(1);
> 
> 
>     private static final ExecutorService executor = new ThreadPoolExecutor(
>             Runtime.getRuntime().availableProcessors(),
>             Runtime.getRuntime().availableProcessors() * 2,
>             5L,
>             TimeUnit.SECONDS,
>             new LinkedBlockingQueue<>(20),
>             new ThreadFactoryBuilder().setNameFormat("ThreadLocal-test-%d").build(),
>             new ThreadPoolExecutor.CallerRunsPolicy());
> 
>     public class RunnableDemo implements Runnable {
>         private String str;
> 
>         private Integer num;
> 
>         public RunnableDemo(String str, Integer num) {
>             this.str = str;
>             this.num = num;
>         }
> 
>         @Override
>         public void run() {
>             try {
> //                semaphore.acquire();
>                 System.out.println(Thread.currentThread().getName() + "intThreadLocal:" + intThreadLocal.get());
>                 System.out.println(Thread.currentThread().getName() + "strThreadLocal:" + strThreadLocal.get());
> 
>                 intThreadLocal.set(num);
>                 strThreadLocal.set(strThreadLocal.get() + " " + str);
> 
>                 System.out.println(Thread.currentThread().getName() + "intThreadLocal:" + intThreadLocal.get());
>                 System.out.println(Thread.currentThread().getName() + "strThreadLocal:" + strThreadLocal.get());
> 
>             } catch (Exception e) {
>                 throw new RuntimeException(e);
>             } finally {
> //                semaphore.release();
>             }
>         }
>     }
> 
>     public void execute() {
>         RunnableDemo demo1 = new RunnableDemo("runnableDemo1", 100);
>         RunnableDemo demo2 = new RunnableDemo("runnableDemo2", 200);
>         RunnableDemo demo3 = new RunnableDemo("runnableDemo3", 300);
>         executor.execute(demo1);
>         executor.execute(demo2);
>         executor.execute(demo3);
>     }
> 
>     public static void main(String[] args) {
>         ThreadLocalDemo threadLocalDemo = new ThreadLocalDemo();
>         threadLocalDemo.execute();
>     }
> ```
>
> 以上面的代码为例，我们分别创建了一个`intThreadLocal`、`strThreadLocal` 和三个线程。三个线程、不加锁同时访问两个ThreadLocal，最终执行结果如下：
>
> ![image-20230309161532553](E:\learn&notes\notes\Java并发编程\images\03-Java并发编程-其他扩展\image-20230309161532553.png)
>
> 我们发现三个线程获取到的`intThreadLocal` 和`strThreadLocal` 的初始值是相同的，有人会怀疑是因为没有加锁，所以线程不安全，可能导致他们获取的是同一个值。我补充锁后再执行，结果如下：
>
> ![image-20230309161838929](E:\learn&notes\notes\Java并发编程\images\03-Java并发编程-其他扩展\image-20230309161838929.png)
>
> 很明显，结果依然相同，这都是 ThreadLocal 的杰作。`intThreadLocal`  和`strThreadLocal`就像局部变量存在于每个线程中。

## ThreadLocal 的工作原理

> 在解释 ThreadLocal 的工作原理之前， 你先自己想想：如果让你来实现 ThreadLocal 的功能，你会怎么设计呢？ThreadLocal 的目标是让不同的线程有不同的变量 V，那最直接的方法就是创建一个 Map，它的 Key 是线程，Value 是每个线程拥有的变量 V， ThreadLocal 内部持有这样的一个 Map 就可以了。你可以参考下面的示意图和示例代码来理解。
>
> ![image-20230309162112322](E:\learn&notes\notes\Java并发编程\images\03-Java并发编程-其他扩展\image-20230309162112322.png)
>
> 那 Java 的 ThreadLocal 是这么实现的吗？这一次我们的设计思路和 Java 的实现差异很 大。Java 的实现里面也有一个 Map，叫做 ThreadLocalMap，不过持有 ThreadLocalMap 的不是 ThreadLocal，而是 Thread。
>
> 我们先看看 ThreadLocalMap.get()方法的实现
>
> ```java
>     /**
>      * Returns the value in the current thread's copy of this
>      * thread-local variable.  If the variable has no value for the
>      * current thread, it is first initialized to the value returned
>      * by an invocation of the {@link #initialValue} method.
>      *
>      * @return the current thread's value of this thread-local
>      */
>     public T get() {
>         Thread t = Thread.currentThread();
>         ThreadLocalMap map = getMap(t);
>         if (map != null) {
>             ThreadLocalMap.Entry e = map.getEntry(this);
>             if (e != null) {
>                 @SuppressWarnings("unchecked")
>                 T result = (T)e.value;
>                 return result;
>             }
>         }
>         return setInitialValue();
>     }
> 
>     /**
>      * Get the map associated with a ThreadLocal. Overridden in
>      * InheritableThreadLocal.
>      *
>      * @param  t the current thread
>      * @return the map
>      */
>     ThreadLocalMap getMap(Thread t) {
>         return t.threadLocals;
>     }
> 
> ```
>
>  从`getMap(t)`方法中，我们可以看到，`ThreadLocalMap map`是从当前线程中获取的。Thread 这个类内部有一个私有属性 threadLocals，其类型就是 ThreadLocalMap，ThreadLocalMap 的 Key 是 ThreadLocal。
>
> ![image-20230309162416787](E:\learn&notes\notes\Java并发编程\images\03-Java并发编程-其他扩展\image-20230309162416787.png)
>
> 你可以结合下面的示意图来理解。
>
> ![image-20230309163017223](E:\learn&notes\notes\Java并发编程\images\03-Java并发编程-其他扩展\image-20230309163017223.png)
>
> 我们的设计方案和 Java 的实现仅仅是 Map 的持有方不同而已，我们的设计里 面 Map 属于 `ThreadLocal`，而 Java 的实现里面`ThreadLocalMap`则是属于`Thread`。这 两种方式哪种更合理呢？很显然 Java 的实现更合理些。在 Java 的实现方案里面，**ThreadLocal 仅仅是一个代理工具类，内部并不持有任何与线程相关的数据，所有和线程 相关的数据都存储在 Thread 里面**，这样的设计容易理解。而从数据的亲缘性上来讲， `ThreadLocalMap`属于`Thread` 也更加合理。
>
> 当然还有一个更加深层次的原因，那就是**不容易产生内存泄露**。在我们的设计方案中， `ThreadLocal`持有的 Map 会持有 `Thread`对象的引用，这就意味着，只要`ThreadLocal`对象存在，那么 Map 中的 `Thread`对象就永远不会被回收。`ThreadLocal`的生命周期往往 都比线程要长，所以这种设计方案很容易导致内存泄露。而 Java 的实现中 `Thread`持有 `ThreadLocalMap`，而且 `ThreadLocalMap`里对 `ThreadLocal`的引用还是弱引用（WeakReference），所以只要 `Thread`对象可以被回收，那么 `ThreadLocalMap`就能被 回收。Java 的这种实现方案虽然看上去复杂一些，但是更加安全。

## ThreadLocal 与内存泄露

> Java 的 `ThreadLocal`实现应该称得上深思熟虑了，不过即便如此深思熟虑，还是不能百分百地让程序员避免内存泄露，例如在线程池中使用 `ThreadLocal`，如果不谨慎就可能导致内存泄露。
>
> 在线程池中使用 `ThreadLocal`为什么可能导致内存泄露呢？原因就出在线程池中线程的存活时间太长，往往都是和程序同生共死的，这就意味着 `Thread`持有的 `ThreadLocalMap`一直都不会被回收，虽然 `ThreadLocalMap`中的 Entry 对 `ThreadLocal`是弱引用 （WeakReference）， 但是 Entry 中的 Value 却是被 Entry 强引用的，所以即便 Value 的生命周期结束了， Value 也是无法被回收的，从而导致内存泄露。
>
> 那在线程池中，我们该如何正确使用 `ThreadLocal`呢？其实很简单，既然 JVM 不能做到自动释放对 Value 的强引用，那我们手动释放就可以了。利用**try{}finally{}方案**了，这个简直就是手动释放资源的利器。
>
> ```java
> ExecutorService es;
> ThreadLocal tl;
> es.execute(()->{
>     //ThreadLocal 增加变量
>     tl.set(obj);
>     try {
>         // 省略业务逻辑代码
>     }finally {
>         // 手动清理 ThreadLocal
>         tl.remove();
>     }
> });
> 
> ```


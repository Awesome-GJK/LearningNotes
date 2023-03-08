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
# 一、可见性、原子性和有序性问题：并发编程Bug的源头

> 这些年，我们的 CPU、内存、I/O 设备都在不断迭代，不断朝着更快的方向努力。但是，在这个快速发展的过程中，有一个**核心矛盾一直存在，就是这三者的速度差异**。
>
> 为了合理利用 CPU 的高性能，平衡这三者的速度差异，计算机体系机构、操作系统、编译程序都做出了贡献，主要体现为：
>
> * CPU 增加了缓存，以均衡与内存的速度差异；
> * 操作系统增加了进程、线程，以分时复用 CPU，进而均衡 CPU 与 I/O 设备的速度差异；
> * 编译程序优化指令执行次序，使得缓存能够得到更加合理地利用。
>
> 同时这些优化也导致了并发程序出现线程安全问题。

## 源头之一：缓存导致的可见性问题

> 一个线程对共享变量的修改，另外一个线程能够立刻看到，我们称为**可见性**。
>
> 多核时代，每颗CPU都有自己的缓存。当多个线程在不同的CPU上执行，这些线程操作的是不同的 CPU 缓存。比如下图中，线程 A 操作的是 CPU-1 上的缓存，而线程 B 操作的是 CPU-2 上的缓存，很明显，这个时候线程 A 对变量 V 的操作对于线程 B 而言就不具备可见性了。这个就属于硬件程序员给软件程序员挖的“坑”。
>
> ![202208141945845.png](https://s2.loli.net/2022/08/14/4t7nQCmcG8e9aEO.png)

## 源头之二：线程切换带来的原子性问题

> 我们把一个或者多个操作在 CPU 执行的过程中不被中断的特性称为**原子性**。
>
> 操作系统做任务切换，可以发生在任何一条**CPU 指令**执行完，所以CPU能保证的原子操作是 CPU 指令级别的。Java 并发程序都是基于多线程的，自然也会涉及到任务切换。高级语言里一条语句往往需要多条 CPU 指令完成，例如上面代码中的count += 1，至少需要三条 CPU 指令。
>
> * 指令 1：首先，需要把变量 count 从内存加载到 CPU 的寄存器；
> * 指令 2：之后，在寄存器中执行 +1 操作；
> * 指令 3：最后，将结果写入内存（缓存机制导致可能写入的是 CPU 缓存而不是内存）。
>
> 对于上面的三条指令来说，我们假设 count=0，如果线程 A 在指令 1 执行完后做线程切换，线程 A 和线程 B 按照下图的序列执行，那么我们会发现两个线程都执行了 count+=1 的操作，但是得到的结果不是我们期望的 2，而是 1。
>
> ![image-20220814195628389](https://s2.loli.net/2022/08/14/Rh1iVXSteumfgjz.png)

## 源头之三：编译优化带来的有序性问题 

> 那并发编程里还有没有其他有违直觉容易导致诡异 Bug 的技术呢？有的，就是有序性。顾名思义，有序性指的是程序按照代码的先后顺序执行。编译器为了优化性能，有时候会改变程序中语句的先后顺序，例如程序中：“a=6；b=7；”编译器优化后可能变成“b=7；a=6；”，在这个例子中，编译器调整了语句的顺序，但是不影响程序的最终结果。不过有时候编译器及解释器的优化可能导致意想不到的 Bug。
>
> 在 Java 领域一个经典的案例就是利用双重检查创建单例对象，例如下面的代码：在获取实例 getInstance() 的方法中，我们首先判断 instance 是否为空，如果为空，则锁定Singleton.class 并再次检查 instance 是否为空，如果还为空则创建 Singleton 的一个实例。
>
> ```java
> public class Singleton {
>     static Singleton instance;
> 
>     static Singleton getInstance() {
>         if (instance == null) {
>             synchronized (Singleton.class) {
>                 if (instance == null)
>                     instance = new Singleton();
>             }
>         }
>         return instance;
>     }
> }
> ```
>
> 理论上这样获取单例模式能够保证线程安全，但是这个getInstance方法并不完美。问题出在哪里呢？我们new操作转成CPU指令分为三步操作：
>
> * 分配一块内存 M；
> * 在内存 M 上初始化 Singleton 对象；
> * 然后 M 的地址赋值给 instance 变量。
>
> 但是JVM编译器优化后，执行顺序是这样的：
>
> * 分配一块内存 M；
> * 将M 的地址赋值给 instance 变量。
> * 最后在内存 M 上初始化 Singleton 对象。
>
> 优化后会出现什么样的问题呢？假设线程A先执行*getInstance()*方法，当执行完后指令2时恰好发生线程切换，切换到线程B上；如果此时线程B也执行*getInstance()*方法，那么线程B在执行第一个判断时发现*instance != null*,所以直接返回*insantce*,而此时*instance*是没有初始化过的，如果这个时候我们访问*instance*的成员变量就可能出现*空指针异常*。
>
> ![202211031032579.png](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211031032579.png)
>
> 所以防止指令重排序，我们可以在静态变量*instance*s加上*volatile* ，避免该情况发生。

# 二、Java内存模型：看Java如何解决可见性和有序性问题

## 什么是 Java 内存模型？

> 导致可见性的原因是缓存,导致有序性的原因是编译优化，那么解决可见性和有序性最直接的办法就是**按需禁用缓存以及编译优化**。
>
> Java内存模型是个很复杂的规范，从程序员的视角看，它的本质就是规范了JVM如何提供按需禁用缓存和编译优化的方法。具体来说，这些方法包括**volatile**、**synchronized**、**final**、以及**六项Happens-Before规则**。

## 使用 volatile 的困惑

> volatile关键字并不是Java语言的特产，在C语言中就有了，它原始的意义就是禁用CPU缓存。
>
> 声明一个volatile变量 `volatile int x = 0`，它表达的是：告诉编译器，对这个变量的读写，不能使用CPU缓存，必须从内存中读写。
>
> 以下面代码为例，假如线程A执行writer() 方法，按照volatile语义，会把变量“v=true”写入内存；假设线程B执行reader() 方法，按照volatile语义，线程B会从内存中读取变量v。如果线程B看到“v==true”时，return返回的变量x值是多少呢？在JDK低于1.5的版本上运行，x可能是42，也可能是0；在JDK1.5以上的版本运行，x等于42。
>
> ```java
> class VolatileExample {
>     
>     int x = 0;
>     
>     volatile boolean v = false;
>     
>     public void writer() {
>         x = 42;
>         v = true;
>     }
>     
>     public int reader(){
>         if(v == true){
>             return x;        //这里的x会是什么呢？
>         }
>     }
> ```
>
> 1.5之前的版本，存在变量x可能被CPU缓存导致可见性问题。而Java内存模型在1.5版本对volatile语义进行了增强，补充了Happens-Before规则。

## Happens-Before规则

> Happens-Before要表达的是：**前面一个操作的结果对后续操作是可见的**。Happens-Before约束了编译器的优化行为，虽然允许编译器优化，但是要求编译器优化后一定遵守Happens-Before规则。
>
> 那么Happens-Before规则具体是哪些规则呢？

### 1、程序的顺序性规则

> 在一个线程中，按照程序顺序，前面的操作Happens-Before于后续的任意操作。继续以之前的代码为例。
>
> ```java
> class VolatileExample {
>     
>     int x = 0;
>     
>     volatile boolean v = false;
>     
>     public void writer() {
>         x = 42;
>         v = true;
>     }
>     
>     public int reader(){
>         if(v == true){
>             return x;        //这里的x会是什么呢？
>         }
>     }
> ```
>
> 按照程序顺序，第6行代码`x=42;`Happens-Before于第7行代码`v=true;`,那么前者对于后者来说是可见的。

### 2、volatile变量规则

> 这条规则是指对于一个volatile 变量的写操作，Happens-Before于后续对这个volatile 变量的读操作，代表禁用缓存。
>
> 光看这一规则，和1.5之前的版本没有什么区别，但是结合传递性规则看，就会不一样了。

### 3、传递性规则

> 这条规则是指如果A `Happens-Before`B，且B`Happens-Before`C，那么A`Happens-Before`C。
>
> 前面提到例子，结合1、2规则来看：
>
> 根据**程序的顺序性规则**，`x=42`对`写变量v=true`可见；
>
> 根据**volatile变量规则**，`写变量v=true`对`读变量v=true`可见；
>
> 再根据**传递性**，`x=42`对`读变量v=true`可见；
>
> 所以线程B能看到`x=42`。
>
> ![image-20221104100105034](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211041001780.png)

### 4、管程中锁的规则

> 这条规则是指对一个锁的解锁` Happens-Before `于后续对这个锁的加锁。管程是一种通用的同步原语，在Java中指的是`synchronized`。
>
> ```java
> / /此处自动加锁
> synchronized (this) {
>    // x 是共享变量, 初始值 =10
>    if (this.x < 12) {
>        this.x = 12;
>    }
> } // 此处自动解锁
> ```
>
> 所以结合规则 4—管程中锁的规则，可以这样理解：假设 x 的初始值是 10，线程 A 执行 完代码块后 x 的值会变成 12（执行完自动释放锁），线程 B 进入代码块时，能够看到线程 A 对 x 的写操作，也就是线程 B 能够看到 x==12。

### 5、线程 start() 规则

> 这条是关于线程启动的。它是指主线程 A 启动子线程 B 后，子线程 B 能够看到主线程在启动子线程B前的操作。
>
> 换句话说就是，如果线程 A 调用线程 B 的 start() 方法（即在线程 A 中启动线程 B），那 么该 start() 操作 Happens-Before 于线程 B 中的任意操作。具体可参考下面示例代码。
>
> ```java
> Thread B = new Thread(()->{
>  // 主线程调用 B.start() 之前
>  // 所有对共享变量的修改，此处皆可见
>  // 此例中，var==77
> });
> // 此处对共享变量 var 修改
> var = 77;
> // 主线程启动子线程
> B.start();
> 
> ```
>
> 

### 6、线程 join() 规则

> 这条是关于线程等待的。它是指主线程 A 等待子线程 B 完成（主线程 A 通过调用子线程 B 的 join() 方法实现），当子线程 B 完成后（主线程 A 中 join() 方法返回），主线程能够看 到子线程的操作。
>
> 换句话说就是，如果在线程 A 中，调用线程 B 的 join() 并成功返回，那么线程 B 中的任意 操作 Happens-Before 于该 join() 操作的返回。具体可参考下面示例代码。
>
> ```java
> Thread B = new Thread(()->{
>  // 此处对共享变量 var 修改
>     var = 66;
> });
> // 例如此处对共享变量修改，
> // 则这个修改结果对线程 B 可见
> // 主线程启动子线程
> B.start();
> B.join()
> // 子线程所有对共享变量的修改
> // 在主线程调用 B.join() 之后皆可见
> // 此例中，var==66
> ```
>

# 三、互斥锁：解决原子性问题

> 原子性问题的源头是**线程切换**，如果能够禁用线程切换那不就能解决这个问题 了吗？而操作系统做线程切换是依赖 CPU 中断的，所以禁止 CPU 发生中断就能够禁止线 程切换。
>
> “原子性”的本质是什么？其实不是不可分割，不可分割只是外在表现，其本质是多个资源间有一致性的要求，操作的**中间状态对外不可见**。
>
> “**同一时刻只有一个线程执行**”这个条件非常重要，我们称之为互斥。如果我们能够保证对共享变量的修改是互斥的，那么，无论是单核 CPU 还是多核 CPU，就都能保证原子性了。

## 锁模型

> 当谈到互斥，我们第一时间想到的解决方案就是`加锁`。下面展示锁模型：
>
> ![202211041454992.png](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211041454992.png)
>
> 首先，临界区将要保护的资源R标注出来；其次，对要保护的资源R创建一把锁LR;最后，在进入进出临界区时对锁LR进行加锁和解锁操作。
>
> 受保护资源R和锁LR的关系非常重要，如果忽略它们之间的关系，会出现自家门锁保护他家资产的情况。

## Java语言提供的锁技术：synchronized

> 锁是一种通用的技术方案，Java语言提供的`synchronized`关键字，就是锁的一种实现。`synchronized`关键字可以用来修饰方法，也可以用来修饰代码块，它的使用示例基本上是下面这样子：
>
> ```java
> class X { 
>     
>     // 修饰非静态方法
>     synchronized void foo() {
>         // 临界区
>     }
>     
>     // 修饰静态方法
>     synchronized static void bar() { 
>         // 临界区 
>     } 
>     
>     // 修饰代码块 
>     Object obj = new Object()；
>     void baz() { 
>         synchronized(obj) { 
>             // 临界区 
>         } 
>     }
> }
> ```
>
> * 当修饰静态方法的时候，锁定的是当前类的 Class 对象，在上面的例子中就 是 Class X。
> * 当修饰非静态方法的时候，锁定的是当前实例对象 this。

## 锁和受保护资源的关系

> 受保护资源和锁之间的关联关系非常重要，他们的关系是怎样的呢？一个合理的关系是：**受保护资源和锁之间的关联关系是 N:1 的关系**。
>
> 当我们要保护多个资源时，首先要区分这些资源是否存在关联关系。

### 1、保护没有关联关系的多个资源

> 假设银行业务中有针对账户余额的取款操作，也有针对账户密码的更改操作，余额和密码都可以看做资源。
>
> 我们可以用一把锁来保护多个资源，例如我们可以用`this`这把锁来管理账户所有资源：账户余额和账户密码。但是用一把锁有个问题，导致取款、查看余额、修改密码、查看密码这四个操作串行化，性能太差。
>
> ```java
> public class Account {
> 
>     /**
>      * 账户余额
>      */
>     private Integer balance;
> 
>     /**
>      * 账户密码
>      */
> 
>     private String password;
> 
>     /**
>      * 取款
>      *
>      * @param amt
>      */
>     synchronized void withdraw(Integer amt) {
>         if (this.balance > amt) {
>             this.balance -= amt;
>         }
>     }
> 
>     /**
>      * 查看余额
>      *
>      * @return
>      */
>     synchronized Integer getBalance() {
>         return balance;
>     }
> 
>     /**
>      * 更改密码
>      *
>      * @param pw
>      */
>     synchronized void updatePassword(String pw) {
>         this.password = pw;
>     }
> 
>     /**
>      * 查看密码
>      *
>      * @return
>      */
>     synchronized String getPassword() {
>         return password;
>     }
> }
> ```
>
> 账户余额和账户密码本身没有任何关联关系，我们可以为账户余额和账户密码分配不同的锁来解决并发问题，这样取款和修改密码就可以并行的操作了。**用不同的锁对受保护的资源进行精细化管理，能够提升性能，这叫锁细化**。
>
> ```java
> public class Account {
>     /**
>      * 锁：保护账户余额
>      */
>     private final Object balLock = new Object();
>      /**
>       * 账户余额
>       */
>     private Integer balance;
>     /**
>      * 锁：保护账户密码
>      */
>    
>     private final Object pwLock = new Object();
>     /**
>      * 账户密码
>       */
>     
>     private String password;
> 
>     /**
>      * 取款
>      * @param amt
>      */
>     void withdraw(Integer amt) {
>         synchronized (balLock) {
>             if (this.balance > amt) {
>                 this.balance -= amt;
>             }
>         }
>     }
> 
>     /**
>      * 查看余额
>      * @return
>      */
>     Integer getBalance() {
>         synchronized (balLock) {
>             return balance;
>         }
>     }
> 
>     /**
>      * 更改密码
>      * @param pw
>      */
>     void updatePassword(String pw) {
>         synchronized (pwLock) {
>             this.password = pw;
>         }
>     }
> 
>     /**
>      * 查看密码
>      * @return
>      */
>     String getPassword() {
>         synchronized (pwLock) {
>             return password;
>         }
>     }
> }
> ```

### 2、保护有关联关系的多个资源

> 如果多个资源是有关联关系的，我们又该如何处理呢？例如银行业务里面的转账操作，账户A向账户B转账，账户A减少100元，账户B增加100元，那么这两个账户就是有关联关系的。
>
> 我们声明了个账户 类：Account，该类有一个成员变量余额：balance，还有一个用于转账的方法： transfer()。我们第一想到的是在转账方法 transfer()上添加`synchronized`关键词。
>
> ```java
> public class Account {
> 
>  /**
>      * 账户余额
>      */
>     private Integer balance;
>     
>     /**
>      * 
>      * @param target
>      * @param amt
>      */
>     synchronized void transfer(
>             Account target, int amt){
>         if (this.balance > amt) {
>             this.balance -= amt;
>             target.balance += amt;
>         }
>     }
> 
> }
> ```
>
> 在这段业务中存在两个资源，分别是A的余额和B的余额。但是`synchronized`锁住的是`this`,`this`这把锁可以保护自己的余额，却不能保护别人的余额。那么如何才能让A对象和B对象共享一把锁呢？
>
> * 方案一：使用唯一对象作为锁
>
> 可以让所有对象都持有一个唯一性的对 象，这个对象在创建 Account 时传入。，我 们把 Account 默认构造函数变为 private，同时增加一个带 Object lock 参数的构造函 数，创建 Account 对象时，传入相同的 lock，这样所有的 Account 对象都会共享这个 lock 了。
>
> ```java
> public class Account {
> 
>     private  Object lock;
> 
>     /**
>      * 账户余额
>      */
>     private Integer balance;
> 
>     public Account(Object lock) {
>         this.lock = lock;
>     }
> 
>     /**
>      * 转账
>      * @param target
>      * @param amt
>      */
>      void transfer(Account target, int amt){
>          //锁住唯一对象lock
>          synchronized (lock){
>              if (this.balance > amt) {
>                  this.balance -= amt;
>                  target.balance += amt;
>              }
>          }
>     }
> 
> }
> ```
>
> 这个方案确实可以解决问题，但是在创建Account对象时必须传入同一个Object lock对象。在真实项目中，创建Account对象的代码很可能分散在多个工程中，传入共享的lock真的很难，所以这个方案缺乏实践的可行性。
>
> * 方案二：用Account.clss作为共享锁
>
> Account.class 是所有 Account 对象共享的，而且这个对 象是 Java 虚拟机在加载 Account 类的时候创建的，所以我们不用担心它的唯一性。使用Account.class作为共享锁，我们就无需在创建Account对象时传入了，代码更简单。
>
> ```java
> public class Account {
> 
>     /**
>      * 账户余额
>      */
>     private Integer balance;
> 
>     /**
>      * 转账
>      * @param target
>      * @param amt
>      */
>      void transfer(Account target, int amt){
>          //锁住唯一对象lock
>          synchronized (Account.class){
>              if (this.balance > amt) {
>                  this.balance -= amt;
>                  target.balance += amt;
>              }
>          }
>     }
> }
> 
> ```
>
> 这个方案相比于方案一，确实优化了不少，但是仍然存在缺点。使用Account.class作为互斥锁，所有的转账操作都会变成串行化，A转账给B 和C转账给D无法并行，性能太低，仍然缺乏实践的可行性。
>
> * 方案三：创建两个细粒度锁
>
> 创建两把锁，分别是转出账本锁和转入账本锁。在 transfer() 方法内部，我们首先尝试锁定转出账户 this（先把转出账本拿到 手），然后尝试锁定转入账户 target（再把转入账本拿到手），只有当两者都成功时，才执行转账操作。这个逻辑可以图形化为下图这个样子。
>
> ![image-20221107154002954](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211071540406.png)
>
> 而至于详细的代码实现，如下所示。经过这样的优化后，账户 A 转账户 B 和账户 C 转账户 D 这两个转账操作就可以并行了。
>
> ```java
> public class Account {
> 
>     /**
>      * 账户余额
>      */
>     private Integer balance;
> 
>     /**
>      * 转账
>      * @param target
>      * @param amt
>      */
>      void transfer(Account target, int amt){
>          //锁住转出账户
>          synchronized (this){
>              //锁定转入账户
>              synchronized (target){
>                  if (this.balance > amt) {
>                      this.balance -= amt;
>                      target.balance += amt;
>                  }
>              }
>          }
>     }
> }
> ```
>
> 相比较用Account.class作为互斥锁，这种方案缩小了锁定范围，属于细粒度锁。**使用细粒度锁可以提高并行度，是性能优化的一个重要手段**。但是**使用细粒度锁是有代价的，这个代价就是可能会导致死锁**。锁的粒度越小，出现死锁的可能性越大。

## 死锁

> 方案三种，我们使用了细粒度的转出锁和转入锁。当A向B转账，B也向A转账时，A和B都获取到了转出锁this（即自身），获取转入锁时，A想要获取的B锁已经被B占有，B想要获取的A锁已经被A占有。于是A和B就一直这么等下去，也就是我们所说的死锁。整个过程可以参考下图：
>
> ![image-20221107160426310](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211071604437.png)
>
> 死锁的定义：**一组互相竞争 资源的线程因互相等待，导致“永久”阻塞的现象**。
>
> ### 如何预防死锁
>
> 并发程序一旦死锁，一般没有特别好的方法，很多时候我们只能重启应用。因此，解决死锁问题最好的办法还是规避死锁。
>
> 要避免死锁就要先分析死锁发生的必要条件：
>
> *  **互斥**，共享资源 X 和 Y 只能被一个线程占用；
> *  **占有且等待**，线程 T1 已经取得共享资源 X，在等待共享资源 Y 的时候，不释放共享资 源 X；
> * **不可抢占**，其他线程不能强行抢占线程 T1 占有的资源；
> * **循环等待**，线程 T1 等待线程 T2 占有的资源，线程 T2 等待线程 T1 占有的资源，就是循环等待。
>
> 也就是说，**只要我们破坏其中一个，就可以成功避免死锁的发生**。其中，互斥条件是我们无法破坏的，因为我们用的锁本身就是互斥。那么其他三个条件我们如何破坏呢？
>
> * 对于“占用且等待”这个条件，我们可以一次性申请所有的资源，这样就不存在等待了。
>
> * 对于“不可抢占”这个条件，占用部分资源的线程进一步申请其他资源时，如果申请不到，可以主动释放它占有的资源，这样不可抢占这个条件就破坏了。
>
> *  对于“循环等待”这个条件，可以靠按序申请资源来预防。所谓按序申请，是指资源是有线性顺序的，申请的时候可以先申请资源序号小的，再申请资源序号大的，这样线性化后自然就不存在循环了。
> 

### 1、破坏占用且等待条件

> 我们需要一个单例管理角色，对外提供“一次性申请所有资源”和“一次性释放所有资源”方法。当账户Account在执行转账操作时，首先向单例管理角色申请转入转出两个资源，申请成功后锁定两个资源执行转账操作；转账操作完成后再向单例管理角色释放转入转出两个资源。代码具体实现如下：
>
> ```java
> /**
>  * Allocator 分配器
>  *
>  * @author: gaojiankang
>  * @date: 2022/11/7 16:44
>  * @description:
>  */
> public class Allocator<T> {
> 
>     private static volatile Allocator<Object> allocator = null;
> 
>     private List<T> list = new ArrayList<>();
> 
>     private Allocator() {
>     }
> 
>     /**
>      * 一次性申请所有资源
>      * @param from
>      * @param to
>      * @return
>      */
>     synchronized boolean apply(T from, T to){
>         if(list.contains(from) || list.contains(to)){
>             return false;
>         }else {
>             list.add(from);
>             list.add(to);
>         }
>         return true;
>     }
> 
>     /**
>      * 一次性释放所有资源
>      * @param from
>      * @param to
>      */
>     synchronized void free(T from, T to){
>         list.remove(from);
>         list.remove(to);
>     }
> 
>     public static <T> Allocator<T> getInstance(){
>         if(allocator == null){
>             synchronized (Allocator.class){
>                 if(allocator == null){
>                     allocator = new Allocator<>();
>                 }
>             }
>         }
>         return (Allocator<T>) allocator;
>     }
> }
> 
> 
> 
> /**
>  * Account 账户
>  *
>  * @author: gaojiankang
>  * @date: 2022/11/7 16:42
>  * @description:
>  */
> public class Account {
> 
> 
>     /**
>      * 转入转出资源分配器
>      *  allocator 为单列
>      */
>     private Allocator<Account> actr;
> 
>     /**
>      * 账户余额
>      */
>     private Integer balance;
> 
>     public Account() {
>         this.actr = Allocator.getInstance();
>     }
> 
>     /**
>      * 转账
>      * @param target
>      * @param amt
>      */
>     void transfer(Account target, int amt){
>         // 自选申请转出账户和转入账户，直到成功
>         while(!actr.apply(this, target)) {}
>         try {
>             //锁住转出账户
>             synchronized (this){
>                 //锁定转入账户
>                 synchronized (target){
>                     if (this.balance > amt) {
>                         this.balance -= amt;
>                         target.balance += amt;
>                     }
>                 }
>             }
>         } finally {
>             // 释放转出账号和转入账号
>             actr.free(this, target);
>         }
>     }
> }
> ```
>
> ### 等待-通知机制优化上面的代码
>
> 上面的代码中，使用了死循环进行循环等待获取资源。如果`Allocator.apply()`执行耗时很短，或者并发量不大的话，那上面的解决方案还可以。一旦`Allocator.apply()`执行时间过长，或者高并发场景，死循环一直占用CPU资源，必然会影响程序性能，甚至CPU爆满，程序瘫痪等问题。
>
> ```java
>         while(!actr.apply(this, target)) {}
> ```
>
> 针对上面的代码，我可以使用 `synchronized` 实现 *等待-通知* 机制进行优化：
>
> 同一时刻，只有一个线程可以获取锁进入临界区。其他线程未获取到锁，会进入锁的同步队列（左）。当进入临界区的线程由于某些条件不满足，调用`wait()`方法释放持有的互斥锁，进入等待队列（右），其他线程就有机会获得 锁，并进入临界区了。
>
> ![image-20221108145157026](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211081452949.png)
>
> 那线程要求的条件满足时，该怎么通知已经进入等待队列（右）的线程呢？通过Java对象的`notify()`和`notifyAll()`方法去唤醒等待队列（右）中的线程。大致过程如下：当条件满足时，调用`notify()`方法，通知等待队列（右）中线程，告诉它**条件曾经满足过**，并将它转移到同步队列（左），再次竞争锁资源。如果此线程再次获取锁，在临界区内需要再判断是否满足条件。因为在它被唤醒到获取锁的过程中，有可能条件已经发生变化了，再次不满足。
>
> ![image-20221108150045919](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211081500511.png)
>
> 等待-通知机制优化后的Allocator代码如下：
>
> ```java
> /**
>  * Allocator 分配器
>  *
>  * @author: gaojiankang
>  * @date: 2022/11/7 16:44
>  * @description:
>  */
> public class Allocator<T> {
> 
>     private static volatile Allocator<Object> allocator = null;
> 
>     private List<T> list = new ArrayList<>();
> 
>     private Allocator() {
>     }
> 
>     /**
>      * 一次性申请所有资源
>      * @param from
>      * @param to
>      * @return
>      */
>     synchronized void apply(T from, T to) throws InterruptedException {
>         while (list.contains(from) || list.contains(to)){
>             //不满足条件，进入等待队列
>             try {
>                 wait();
>             } catch (InterruptedException e) {
>                 e.printStackTrace();
>             }
>         }
>         //获取两个资源
>         list.add(from);
>         list.add(to);
>     }
> 
>     /**
>      * 一次性释放所有资源
>      * @param from
>      * @param to
>      */
>     synchronized void free(T from, T to){
>         list.remove(from);
>         list.remove(to);
>         notifyAll();
>     }
> 
>     public static <T> Allocator<T> getInstance(){
>         if(allocator == null){
>             synchronized (Allocator.class){
>                 if(allocator == null){
>                     allocator = new Allocator<>();
>                 }
>             }
>        }
>         return (Allocator<T>) allocator;
>     }
> }
> ```
>
> notify() 是会随机地通知等待队列中的一个线程，而 notifyAll() 会通知等待队列中的所有线程。从感觉上来讲，应该是 notify() 更好一些，因为即便通知所有线程，也只有一个线程能够进入临界区。但那所谓的感觉往往都蕴藏着风险，实际上使用 notify() 也很有风险，它的风险在于可能导致某些线程永远不会被通知到。
>
> **尽量使用 notifyAll() **。

### 2、破坏不可抢占条件

> 破坏不可抢占条件看上去很简单，核心是要能够主动释放它占有的资源，这一点 synchronized 是做不到的。原因是 synchronized 申请资源的时候，如果申请不到，线程 直接进入阻塞状态了，而线程进入阻塞状态，啥都干不了，也释放不了线程已经占有的资源。但是java.util.concurrent 这个包下面提供的 Lock 是可以轻松解决这个问题的。

### 3、破坏循环等待条件

> 破坏这个条件，需要对资源进行排序，然后按序申请资源。这个实现非常简单，我们假设每 个账户都有不同的属性 id，这个 id 可以作为排序字段，申请的时候，我们可以按照从小到大的顺序来申请。代码如下：
>
> ```java
>  public class Account {
>  
>      /**
>       * 序号
>       */
>      private int id;
> 
>     /**
>      * 余额
>      */
>     private Integer balance;
> 
>     void transfer(Account target, int amt) {
>         //根据Id，控制获取资源先后顺序
>         Account left = target;
>         Account right = this;
>         if(target.id > this.id){
>             right = target;
>             left = this;
>         }
>         //先锁序号小的
>         synchronized (left){
>             //再锁序号大的
>             synchronized (right){
>                 if(balance > amt){
>                     balance -= amt;
>                     target.balance += amt;
>                 }
>             }
>         }
>     }
> }
> ```

# 四、安全性、活跃性以及性能问题

## 安全性问题

> 什么是线程安全呢？其实本质上就是正确性，而正确性的含义就是**程序按照我们期望的执 行，不要让我们感到意外**。
>
> 已知缓存会带来可见性问题、线程切换会带来原子性问题、编译优化会带来有序性问题，实际开发中，我们不可能对每一处代码都分析得到这么细致。只有一种场景会出现线程安全问题：**存在共享数据并且该数据会发生变化，通俗地讲就是有多个线程会同时读写同一数据**。如果能够保证不存在共享数据或者该数据不会发生变化，那就不会存在线程安全问题。有不少技术是基于这个理论，例如：线程本地存储Thread Local Storage， TLS）、不变模式等等。
>
> 在现实生活中，共享数据并且会发生变化的场景有很多。当多个线程同时访问同一个数据，并且至少有一个线程会进行写操作，如果我们不做任何处理，必然会出现bug ，对此还有一个专业术语，叫做**数据竞争(Data Race)**。
>
> 既然存在数据竞争，那我们是不是加个锁就可以解决问题了呢？看看下面代码示例。`add10K()`方法内通过`get()`和`set()`方法对`num`进行读写操作，我们分别在`get()`和`set()`方法上添加`synchronized`关键字，那么就不存在数据竞争问题，但是`add10K()`方法仍然存在线程安全问题。
>
> ```java
> public class Test {
> 
>     private long num;
> 
>     public synchronized long getNum() {
>         return num;
>     }
> 
>     public synchronized void setNum(long num) {
>         this.num = num;
>     }
> 
>     void add10K(){
>         int idx = 0;
>         while (idx< 10000){
>             setNum(getNum()+1);
>             idx++;
>         }
>     }
> 
>     public static void main(String[] args) throws InterruptedException {
>         Test test = new Test();
>         Thread thread1 = new Thread(new Runnable() {
>             @Override
>             public void run() {
>                 System.out.println("Thread1-" + Thread.currentThread().getName() + "startTime:" + DateUtil.date().toMsStr());
>                 test.add10K();
>                 System.out.println("Thread1-" + Thread.currentThread().getName() + "endTime:" + DateUtil.date().toMsStr());
>             }
>         });
>         Thread thread2 = new Thread(new Runnable() {
>             @Override
>             public void run() {
>                 System.out.println("Thread2-" + Thread.currentThread().getName() + "startTime:" + DateUtil.date().toMsStr());
>                 test.add10K();
>                 System.out.println("Thread2-" + Thread.currentThread().getName() + "endTime:" + DateUtil.date().toMsStr());
>             }
>         });
>         thread1.start();
>         thread2.start();
>         thread1.join();
>         thread2.join();
>         System.out.println(test.num);
>     }
> ```
>
> 假设 count=0，当两个线程同时执行 get() 方法时，get() 方法会返回相同的值 0，两个线 程执行 get()+1 操作，结果都是 1，之后两个线程再将结果 1 写入了内存。你本来期望的是 2，而结果却是 1。
>
> 这种问题，称之为**竞态条件(Race Condition)**，也就是**程序的执行结果依赖线程执行的顺序**。那面对数据竞争和竞态条件问题，又该如何保证线程的安全性呢？其实这两类问题，都可以用互斥这个技术方案，也就是加锁，加上正确的锁。

## 活跃性问题

> 所谓活跃性问题，指的是某个操作无法执行下去。我们常见的死锁就是一种典型的活跃性问题，当然除了**死锁**外，还有两种情况，分别是**活锁**和**饥饿**。
>
> * ### 活锁
>
> 死锁的发生是因为线程会互相等待，而且会一直等待下去，在技术上的表现形式是线程永久地阻塞了，而活锁与之相反。**有时线程虽然没有发生阻塞，但是仍然会存在执行不下去的情况，这就是活锁**。
>
> 可以类比现实中例子，甲乙两个人相向而行。快要遇见时，两人为了不相撞，互相谦让，甲走自己的右手边，乙走自己的左手边，结果两人又相撞了。我相信现实中，我们一定经历过这样的尴尬场景。解决“活锁”的方案很简单，谦让时，**尝试等待一个随机的时间**就可以了。
>
> * ### 饥饿
>
> 那“饥饿”该怎么去理解呢？所谓“饥饿”指的是**线程因无法访问所需资源而无法执行下去的情况**。“不患寡，而患不均”，如果线程优先级“不均”，在 CPU 繁忙的情况下，优先级低的线程得到执行的机会很小，就可能发生线程“饥饿”；持有锁的线程，如果执行的时间过长，也可能导致“饥饿”问题。
>
> 解决“饥饿”问题的方案很简单，有三种方案：一是**保证资源充足**，二是**公平地分配资源**， 三就是**避免持有锁的线程长时间执行**。这三个方案中，方案一和方案三的适用场景比较有限，因为很多场景下，资源的稀缺性是没办法解决的，持有锁的线程执行的时间也很难缩短，倒是方案二的适用场景相对来说更多一些。
>
> 那如何公平地分配资源呢？在并发编程里，主要是使用**公平锁**。所谓公平锁，是一种先进先出的方案，线程的等待是有顺序的，排在等待队列前面的线程会优先获得资源。

## 性能问题

> 使用“锁”要非常小心，但是如果小心过度，也可能出“性能问题”。“锁”的过度使用可能导致串行化的范围过大，这样就不能够发挥多线程的优势了，而我们之所以使用多线程搞并发程序，为的就是提升性能。
>
> 那么串行对性能的影响是怎么样的呢？有个阿姆达尔（Amdahl）定律，代表了处理器并行运算之后效率提升的能力，我们通过这个公式看看串行的影响。
>
> ![image-20221109152133681](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211091521921.png)
>
> 公式里的 `n` 可以理解为 `CPU 的核数`，`p` 可以理解为`并行百分比`，那`（1-p）`就是`串行百分比`了。假设我们的`串行百分比`是5%，`CPU 的核数n`无穷大,那么`加速比S`的极限就是20倍。也就是说，如果我们的串行百分比是5%，无论我们采用什么方案，程序的性能也就只能提高20倍。
>
> 所以使用锁的时候一定要关注对性能的影响。 那怎么才能避免锁带来的性能问题呢？这个问题很复杂，**Java SDK 并发包里之所以有那么多东西，有很大一部分原因就是要提升在某个特定领域的性能**。
>
> 不过从方案层面，我们可以这样来解决这个问题：
>
> * 第一，既然使用锁会带来性能问题，那最好的方案自然就是**使用无锁的算法**和**数据结构**了。 在这方面有很多相关的技术，例如线程本地存储 (Thread Local Storage, TLS)、写入时复制 (Copy-on-write)、乐观锁等；Java 并发包里面的原子类也是一种无锁的数据结构； Disruptor 则是一个无锁的内存队列，性能都非常好……
> * 第二，减少锁持有的时间。互斥锁本质上是将并行的程序串行化，所以要增加并行度，一定要减少持有锁的时间。这个方案具体的实现技术也有很多，例如使用细粒度的锁，一个典型 的例子就是 Java 并发包里的 ConcurrentHashMap，它使用了所谓分段锁的技术；还可以使用读写锁，也就是读是无锁的，只有写的时候才会互斥。
>
> 性能方面的度量指标有很多，我觉得有三个指标非常重要，就是：**吞吐量**、**延迟**和**并发量**。
>
> *  吞吐量：指的是单位时间内能处理的请求数量。吞吐量越高，说明性能越好。
> *  延迟：指的是从发出请求到收到响应的时间。延迟越小，说明性能越好。
> *  并发量：指的是能同时处理的请求数量，一般来说随着并发量的增加、延迟也会增加。 所以延迟这个指标，一般都会是基于并发量来说的。例如并发量是 1000 的时候，延迟 是 50 毫秒。

# 五、管程：并发编程的万能钥匙

## 什么是管程

> 为什么 Java 在 1.5 之前仅仅提供了 `synchronized` 关键字及 `wait()`、`notify()`、`notifyAll()` 这三个方法？在大学的操作系统原理中，我们知道`信号量`能够解决所有并发问题，Java是不是采用的`信号量`呢？
>
> 实际上Java采用的是`管程`技术，`synchronized` 关键字及` wait()`、`notify()`、`notifyAll()` 这三个方法都是`管程`的组成部分。而`管程`和`信号量`是等价的，所谓等价指的是用`管程`能够实现`信号量`，也能用`信号量`实现`管程`。但是`管程`更容易使用，所以 Java 选择了`管程`。
>
> `管程`，对应的英文是`Monitor`。之前在网上翻阅`Synchronized`关键字原理时，经常会看到`Monitor`，其实在操作系统领域一般都翻译成`管程`。**所谓的管程，就是指管理共享变量以及对共享变量的操作过程**。

## MESA模型

> 在管程的发展史中，先后出现过三种不同的管程模型，分别是：`Hasen模型`、`Hoare模型`和`MESA模型`。其中，现在广泛应用的是`MESA模型`，并且Java管程的实现参考的也是`MESA模型`。
>
> 在并发编程领域，有两大核心问题：一个是`互斥`，即同一时刻只允许一个线程访问共享资 源；另一个是`同步`，即线程之间如何通信、协作。这两大问题，管程都是能够解决的。
>
> 我们先来看看管程是如何解决互斥问题的。管程解决互斥问题的思路很简单，就是将共享变量及其对共享变量的操作统一封装起来。参考下图，`管程X`将共享变量`queue队列`及相关的操作`入队enq()`、`出队deq()`都封装起来了；线程A和线程B如果想访问共享变量`queue`，只能通过调用管程提供的`enq()`、`deq()`方法来实现；`enq()`、`deq()`保证互斥性，只允许一个线程进入管程。
>
> ![image-20221109192600222](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211091926549.png)
>
> 管程模型和面向对象高度契合的，估计这也是Java选择管程的原因吧，前面学习的互斥锁用法，其背后的原因其实就是他。
>
> 那管程如何解决线程间的同步问题呢？
>
> 下面展示了MESA模型示意图，它详细描述了MESA模型的主要组成部分。在管程模型里面，共享变量及对共享变量的操作是被封装起来的，图中最外层的框就代表封装的意思。框的上面只有一个入口，并且在入口旁边还有一个入口等待队列。当多个线程同时试图进入管程内部时，只允许一个线程进入，其他线程则在入口等待队列中等待。
>
> ![image-20221109192906785](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211091929029.png)
>
> 那么条件变量和条件变量等待队列的作用是什么呢？当线程A获取锁，进入临界区时，由于条件变量A不满足，调用wait()方法后，线程A进去条件等待队列。所以条件变量和条件变量等待队列是用来解决线程同步问题的。
>
> 当线程B获取锁，进入临界区后，条件变量A满足了，则调用notify()方法，通知条件变量A的等待队列中的某一个线程（假设只有线程A）。线程A被通知到后，会从条件变量等待队列出来，重新进入入口等待队列中。
>
> 阻塞队列完美展现了管程解决同步和互斥的过程。阻塞队列有两个操作分别是入队和出队，这两个方法都是先获取互斥锁，类比管程模型中的入口。 
>
> * 对于入队操作，如果队列已满，就需要等待直到队列不满；
> * 对于出队操作，如果队列为空，就需要等待直到队列不空； 
> * 如果入队成功，那么队列就不空了，就需要通知条件变量：队列不空notEmpty对应的等待队列；
> * 如果出队成功，那就队列就不满了，就需要通知条件变量：队列不满notFull对应的等待队列。
>
> 下面展示阻塞队列的代码
>
> ```java
> public class BlockedQueue {
>     private final Object[] objects;
> 
>     private final Lock lock = new ReentrantLock();
> 
>     /**
>      * 条件变量 队列不满
>      */
>     private final Condition notFull = lock.newCondition();
> 
>     /**
>      * 条件变量 队列不空
>      */
>     private final Condition notEmpty = lock.newCondition();
> 
>     private int index = 0;
> 
>     public BlockedQueue(int num) {
>         this.objects = new Object[num];
>     }
> 
>     /**
>      * 入队
>      */
>     public void enq(Object x){
>         lock.lock();
>         try {
>             while(index > objects.length -1){
>              //队列已满，进入notFull条件等待队列
>                 notFull.await();
>             }
>             //插入队列
>             objects[index] = x;
>             index++;
>             //通知出队操作，唤醒notEmpty条件等待队列中的线程
>             notEmpty.signal();
>         } catch (InterruptedException e) {
>             e.printStackTrace();
>         } finally {
>             lock.unlock();
>         }
> 
>     }
> 
>     /**
>      * 出队
>      */
>     public Object deq(){
>         Object object = null;
>         lock.lock();
>         try {
>             while (index == 0 ){
>                 //队列为空,进入notEmpty条件等待队列
>                 notEmpty.await();
>             }
>             //抛出队列
>             object = objects[index];
>             objects[index] = null;
>             index--;
>             //通知入队操作,唤醒notFull条件等待队列中的线程
>             notFull.signal();
>         } catch (InterruptedException e) {
>             e.printStackTrace();
>         }finally {
>             lock.unlock();
>         }
>         return object;
>     }
> 
> }
> ```

## 各个管程模型之间的区别

> 对于MESA管程来说，有一个编程范式，这个是MESA管程特有的。
>
> ```java
> while (条件不满足) ｛
>      wait();    
> ｝
> ```
>
> Hasen 模型、Hoare 模型和 MESA 模型的一个核心区别就是当条件满足后，如何通知相关线程。管程要求同一时刻只允许一个线程执行，那当线程 T2 的操作使线程 T1 等待的条件满足时，T1 和 T2 究竟谁可以执行呢？
>
> * Hasen模型，要求notify()放在代码的最后，这样T2通知完T1后，T2就结束了，然后T1再执行，这样就能保证同一时刻只有一个线程执行。
> * Hoare模型，T2通知完T1后，T2阻塞，T1马上执行；等T1执行完，再唤醒T2，也能够保证同一时刻只有一个线程执行。但是相比Hasen模型，T2多了一次阻塞唤醒操作。
> * MESA模型，T2通知完T1后，T2还是会接着执行，T1并不会立即执行，仅仅是从条件变量等待队列中转移到入口等待队列中。这样的好处是notify()不用放在代码最后，T2本身也没有多余的阻塞唤醒操作。但是有一个副作用，就是T1再次执行时，可能曾经条件满足，但是此刻不满足，所有需要以循环方式检验条件变量。

## Java中的管程

> Java参考了MESA模型，`synchronized`关键字是对MESA模型的精简。MESA模型中，条件变量可以有多个，Java内置的管程只有一个条件变量，具体如下图：
>
> ![image-20221110150003961](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211101500161.png)

# 六、Java线程

## 通用的线程生命周期

> 线程是操作系统里的一个概念，Java语言里的线程本质上就是操作系统的线程。在操作系统层面，线程也有“生老病死”，专业的说法叫有生命周期。对于有生命周期的事物，要学好它，思路非常简单，只要能搞懂**生命周期中各个节点的状态转换机制**就可以了。
>
> 通用的线程生命周期基本上可以用下图这个“五态模型”来描述。这五态分别是：初始状态、可运行状态、运行状态、休眠状态和终止状态。
>
> ![image-20221110154902327](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211101549536.png)
>
> * `初始状态`，指的是线程已经被创建，但是还不允许分配 CPU 执行。这个状态属于编程语言特有的，仅仅实在编程语言层面被创建，而在操作系统层面，真正的线程还没有被创建。
> * `可运行状态`，指的是线程可以分配 CPU 执行，在这种状态下，操作系统线程已经被创建成功了。
> * `运行状态`，可运行状态的线程得到CPU使用权后的状态。
> * `休眠状态`，运行状态的线程调用阻塞Api或者等待条件变量满足时，线程进入休眠状态。进入休眠状态的线程释放CPU使用权，处于休眠状态的线程永远没有机会获取CPU使用权。当等待的条件满足后，线程转为可运行状态，再次竞争CPU使用权。
> * `终止状态`，线程执行完或者出现异常就会进入终止状态，代表生命周期结束。进入终止状态的线程不会切换到其他任何状态。

## Java线程的生命周期

> Java语言细化了通用生命周期中的休眠状态，所以Java语言中的线程共有6种状态，分别是:
>
> *  NEW（初始化状态）
> *  RUNNABLE（可运行 / 运行状态）
> * BLOCKED（阻塞状态）
> *  WAITING（无时限等待）
> *  TIMED_WAITING（有时限等待）
> *  TERMINATED（终止状态）
>
> Java 线程中的 BLOCKED、WAITING、TIMED_WAITING 是对休眠状态的细分，对于操作系统，这三种状态都是休眠状态，所有**这三个状态的线程永远没有CPU使用权**。
>
> ![image-20221110160315664](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211101603192.png)
>
> 下面我们看看各状态之间是如何状态的。

### 1、RUNNABLE 与 BLOCKED 的状态转换

> 只有一种场景会触发这种状态转换，就是线程等待synchronized的隐式锁。同一时刻只允许一个线程执行，其他线程只能等待。此时等待的线程就会从 RUNNABLE 转换到 BLOCKED 状态。而当等待的线程获得 synchronized 隐式锁时，就又会从 BLOCKED 转换到 RUNNABLE 状态。

### 2、RUNNABLE 与 WAITING 的状态转换

> 总体来说，有三种场景会触发这种转换:
>
> * 第一种场景，线程获得synachronized隐式锁后调用了无参数的 Object.wait()  方法。
> * 第二种场景，调用无参数的 Thread.join() 方法。例如在线程B中调用线程A的join()方法，线程B等待线程A执行完成，其状态会从 RUNNABLE 转换到 WAITING。当线程 thread A 执行完，原来线程B又会从 WAITING 状态转换到 RUNNABLE。
> * 第三种场景，调用 LockSupport.park() 方法。Java并发包中的锁都是基于它实现的。调用 LockSupport.park() 方法，当前线程会阻塞，线程的状态会从 RUNNABLE 转换到 WAITING。调用 LockSupport.unpark(Thread thread) 可唤醒目标线程，目标线程的状态又会从 WAITING 状态转换到 RUNNABLE。

### 3、RUNNABLE 与 TIMED_WAITING 的状态转换

> 有五种场景会触发这种转换：
>
> * 1、调用带超时参数的 Thread.sleep(long millis) 方法；
> * 2、获得 synchronized 隐式锁的线程，调用带超时参数的 Object.wait(long timeout) 方 法；
> * 3、调用带超时参数的 Thread.join(long millis) 方法；
> * 4、调用带超时参数的 LockSupport.parkNanos(Object blocker, long deadline) 方法；
> * 5、调用带超时参数的 LockSupport.parkUntil(long deadline) 方法。

### 4、从 NEW 到 RUNNABLE 状态

> Java 刚创建出来的 Thread 对象就是 NEW 状态，而创建 Thread 对象主要有两种方法。一种是继承 Thread 对象，重写 run() 方法。示例代码如下：
>
> ```java
> // 自定义线程对象
> class MyThread extends Thread {
>  public void run() {
>  // 线程需要执行的代码
>  ......
>  }
> }
> // 创建线程对象
> MyThread myThread = new MyThread();
> 
> ```
>
> 另一种是实现 Runnable 接口，重写 run() 方法，并将该实现类作为创建 Thread 对象的参数。示例代码如下：
>
> ```java
> // 实现 Runnable 接口
> class Runner implements Runnable {
>  @Override
>  public void run() {
>  // 线程需要执行的代码
>  ......
>  }
> }
> // 创建线程对象
> Thread thread = new Thread(new Runner());
> ```
>
> NEW 状态的线程，不会被操作系统调度，Java 线程要执行，就必须转换到 RUNNABLE 状态。从 NEW 状态转换到 RUNNABLE 状态很简单，只要调用线程对象的 start() 方法就可以了，示例代码如下：
>
> ```java
> MyThread myThread = new MyThread();
> // 从 NEW 状态转换到 RUNNABLE 状态
> myThread.start()；
> 
> ```

### 5、从 RUNNABLE 到 TERMINATED 状态

> 有五种场景会触发这种转换：
>
> * 1、线程执行完 run() 方法后，会自动转换到 TERMINATED 状态。
> * 2、线程执行 run() 方法的过程中抛出异常，也会导致线程转换到 TERMINATED 状态。
> * 3、 Thread 类的stop()方法，不过已经标记为 @Deprecated，不建议使用。
> * 4、正确的姿势其实是调用 interrupt() 方法。
>
> 那 stop() 和 interrupt() 方法的主要区别是什么呢？
>
> stop() 方法会真的杀死线程，如果线程持有 ReentrantLock 锁，被 stop() 的线程并不会自动调用 ReentrantLock 的 unlock() 去释放锁，那其他线程就再也没机会获得 ReentrantLock 锁，这实在是太危险了。所以该方法就不建议使用了，类似的方法还有 suspend() 和 resume() 方法。
>
> 而 interrupt() 方法就温柔多了，interrupt() 方法仅仅是通知线程，**对线程中断标志位进行标记**，线程有机会执行一些后续操作，同时也可以无视这个通知。被 interrupt 的线程，是怎么收到通知的呢？一种是异常，另一种是主动检测。
>
> 当线程 A 处于 WAITING、TIMED_WAITING 状态时，如果其他线程调用线程 A 的 interrupt() 方法，会使线程 A 返回到 RUNNABLE 状态，同时**线程 A 的代码会触发 InterruptedException 异常，并清除线程A中断标记为的标志**。上面我们提到转换到 WAITING、TIMED_WAITING 状态的 触发条件，都是调用了类似 wait()、join()、sleep() 这样的方法，我们看这些方法的签名， 发现都会 throws InterruptedException 这个异常。这个异常的触发条件就是：其他线程 调用了该线程的 interrupt() 方法。
>
> 当线程 A 处于 RUNNABLE 状态时，并且阻塞在 java.nio.channels.InterruptibleChannel 上时，如果其他线程调用线程 A 的 interrupt() 方法，线程 A 会触发 java.nio.channels.ClosedByInterruptException 这个异常；而阻塞在 java.nio.channels.Selector 上时，如果其他线程调用线程 A 的 interrupt() 方法，线程 A 的 java.nio.channels.Selector 会立即返回。
>
> 上面这两种情况属于被中断的线程通过异常的方式获得了通知。还有一种是主动检测，如果 线程处于 RUNNABLE 状态，并且没有阻塞在某个 I/O 操作上。如果其他线程调用线程 A 的 interrupt() 方法，那么线程 A 可以通过 isInterrupted() 方法，检测是不是自己被中断了。

## 创建多少线程才合适

> 为什么要使用多线程？
>
> 使用多线程的本质就是提升程序性能。性能这个词本身是很抽象的，实际上我们可以通过两个核心度量指标来观察，分别是`延迟`和`吞吐量`。提升性能，从度量角度，主要是**降低延迟，提高吞吐量**。
>
> 要想降低延迟，提高吞吐量，可以从两个方向下手，一个是**优化算法**，另一个是**将硬件的性能发挥到极致**。前者属于算法范畴，后者则和并发编程息息相关。计算机主要硬件是`I/O`和`CPU`。简言之， **在并发编程领域，提升性能本质上就是提升硬件的利用率，再具体点来说，就是提升 I/O 的利用率和 CPU 的利用率**。
>
> 如何提升CPU和I/O的利用率呢？假设程序按照CPU和I/O操作交叉执行的方式运行，而且两者耗时都是1:1。
>
> 如下图所示，如果只有一个线程，执行 CPU 计算的时候，I/O 设备空闲；执行 I/O 操作的时候，CPU 空闲，所以 CPU 的利用率和 I/O 设备的利用率都是 50%。
>
> ![image-20221110172015094](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211101720912.png)
>
> 如果有两个线程，如下图所示，当线程 A 执行 CPU 计算的时候，线程 B 执行 I/O 操作； 当线程 A 执行 I/O 操作的时候，线程 B 执行 CPU 计算，这样 CPU 的利用率和 I/O 设备的利用率就都达到了 100%。
>
> ![image-20221110171752878](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211101717781.png)
>
> 通过上面的图示，很容易看出：单位时间处理的请求数量翻了一番，也就是说吞吐量提 高了 1 倍，延迟降低了1倍。如果 CPU 和 I/O 设备的利用率都很低，那么可以尝试**通过增加线程来提高吞吐量，降低延迟**。
>
> 那么到底创建多少线程才能性能提高到最高呢？
>
> 我们程序一般都是CPU计算和I/O操作交叉执行的。由于I/O设备的速度相对于CPU都是很慢的，所以大部分情况I/O操作执行时间都比CPU计算时间长，这种场景我们称为**I/O密集型**，与之相反的就是**CPU密集型**。
>
> I/O 密集型程序和 CPU 密集型程序，计算最佳线程数的方法是不同的。下面我们对这两个场景分别说明。
>
> * 对于CPU密集型，提升性能的终极目标就是提升多核CPU的利用率，过多的线程反而增加了线程切换的成本，所以**线程梳理 = CPU核数 + 1**。`+1`的目的是防止某个在执行的线程出现内存页失效或者其他原因导致阻塞时，这个额外的线程可以顶上，从而保证CPU利用率。
> * 对于I/O密集型，我们要参考CPU计算和I/O操作的耗时比。根据耗时比，设置线程数，控制CPU计算和I/O操作完美交叉进行，以致CPU和I/O的利用率达到100%。所以我们可以得到最佳线程数公式如下：                                                                 最佳线程数 = `CPU核数` * [ `1` + ( `I/O耗时` / `CPU耗时` )]

## 为什么局部变量是线程安全的

> 很多人知道局部变量不存在数据竞争的，但是至于原因嘛，就说不清楚了。首先局部变量都是在方法内部的，我们先看看方法是如何执行的。
>
> 有三个方法 A、B、C，他们的调用关系是 A->B->C（A 调用 B，B 调用 C），在运行时，会构建出下面这样的调用栈。每个方法在调用栈里都有自己的独立空间，称为**栈帧**， 每个栈帧里都有对应方法需要的参数和返回地址。当调用方法时，会创建新的栈帧，并压入 调用栈；当方法返回时，对应的栈帧就会被自动弹出。也就是说，**栈帧和方法是同生共死 的**。
>
> ![image-20221111113228716](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211111132543.png)
>
> 局部变量的作用域是方法内部，局部变量和方法同生共死，栈帧和方法是同生共死的。很显然，**局部变量就是放到了调用栈里**。于是调用栈的结构就变成了下图这样。一个变量如果想跨越方法的边界，即共享变量，就必须创建在堆里。
>
> ![image-20221111113534168](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202211111136692.png)
>
> 每个线程都有自己独立的调用栈，局部变量保存在线 程各自的调用栈里面，不会共享，所以自然也就没有并发问题。
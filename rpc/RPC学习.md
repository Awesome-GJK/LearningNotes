# 一、核心原理：能否画张图解释下RPC的通信流程？

## 什么是RPC

> RPC 的全称是 Remote Procedure Call，即远程过程调用。RPC的作用体现在两个方面：
>
> * **屏蔽远程调用和本地调用的区别，让我们感觉就是调用项目内的方法**
> * **隐藏底层网络通信的复杂性，让我们更专注与业务代码逻辑**

## RPC通信流程

> RPC是一个远程调用，那肯定需要通过网络来传输数据，并且RPC常用于业务系统之间的数据交互，需要保证其可靠性，所以**RPC一般默认采用TCP协议来传输数据**。
>
> RPC能够帮助我们的应用透明地完成远程调用，发起请求的一方叫做调用方，被调用的一方叫做服务提供方。为了实现这个目标，我们需要在RPC框架里面对整个通信细节进行封装。那么完整的RPC会涉及哪些步骤呢？
>
> * 网络传输数据必须是二进制数据，但是调用方请求的参数都是对象，所以需要通过**序列化**方式将参数转为二进制数据。
> * 调用方通过TCP传输请求数据包，服务提供方从TCP通道里面接收二进制数据包。**数据包分成两部分，分别是数据头和消息体**。
>   * **数据头一般用于身份识别，包括协议标识，数据大小，请求类型，序列化类型等信息**；
>   * **消息体主要是请求的业务参数信息和扩展属性等**
> * 服务提供方通过**反序列化**将二进制消息体逆向还原成请求对象，完成真正的方法调用。
> * 完成方法调用后，服务提供方将执行结果**序列化**，回写到对应的TCP通道。
> * 调用方获取到应答的数据包后，将数据包**反序列化**成应答对象
>
> 到这里，一个简版的RPC框架步骤就完成了。整个流程如下：
>
> ![image-20220811235259700](https://s2.loli.net/2022/08/13/IHKQUzeEpTwk5ZF.png)

## RPC应用场景

> 无论是大型分布式应用系统还是中小型系统中，应用架构最终都会从**单体**演进成**微服务化**，整个系统都会被拆分成多个不同功能的应用，并将它们部署在不同的服务器中，而各应用之间会通过RPC进行通信，可以说RPC是整个分布式应用系统的“经络”。
>
> **RPC框架可以帮助我们解决系统拆分后带来的通信问题，并且能让我们像调用本地一样去调用远程方法**。利用RPC框架，不仅可以**很方便地将应用系统架构从“单体”演进成“微服务化”**，而且还能**解决实际开发过程中的效率低下，系统耦合等问题**。
>
> RPC不仅可以解决通信问题，它还被应用在很多场景，比如：**发MQ**、**分布式缓存**、**数据库**等。
>
> ![image-20220813161225300](https://s2.loli.net/2022/08/13/YTyObmv3rR9FN76.png)

# 二、协议：怎么设计可扩展且向后兼容的协议？、

> HTTP 协议和RPC 协议都是属于**应用层协议**。

## HTTP协议

> 我们先了解一下HTTP协议。HTTP协议，是我们日常工作中用的最频繁的协议了，每天打开浏览器的网页就是使用的HTTP协议。**当我们在浏览器里面输入一个URL，浏览器会解析DNS,再将收到的命令封装成一个请求数据包，并将请求数据包发送到DNS解析出来的IP上**。通过抓包工具，我们可以拿到请求的数据包。如下图所示：
>
> ![image-20220813163429205](https://s2.loli.net/2022/08/13/ANTq6wnPrI87amY.png)
>
> HTTP协议的数据包大小相对请求数据本身要大很多，有需要加入很多无用内容，比如换行符号、回车符等。HTTP协议是一个**无状态协议**，客户端无法将请求和响应绑定，每次请求都需要重新建立连接，等响应返回后再关闭连接，所以HTTP协议需要将请求参数的所有二进制数据全部发送到服务提供方，并且同步等待响应。所以HTTP协议是**同步**的。

## RCP协议

> 而RPC负责各应用之间的通信，对性能要求相对更高。RPC并不会将请求参数的所有二进制数据封装成一个数据包发送到服务提供方，中间可能是拆分成多个数据包，也可能会合并其它请求的数据包。

### 不定长RPC协议

> 对于服务提供方，它从TCP通道中收到很多二进制数据，它是怎么识别哪些二进制数据是第一个请求的呢？在传输数据时，为了能够准确“断句”，RPC在发送的二进制数据包中**添加了消息边界标识，用于标识请求数据的结束位置**。RPC每次发请求的大小都是不固定的，为了能让服务提供方准确地读出不定长的内容，我们可以先读取固定一个长度（比如4个字节）用来保存整个请求数据大小。这样在收到数据时，我们先读取固定长度的位置里面带的值，这个值代表协议体的长度，然后在根据值得大小读取协议体的数据。整个协议设计如下：
>
> ![image-20220813180252140](https://s2.loli.net/2022/08/14/sSCfQ4Ackqjl5Gu.png)

### 定长RPC协议

> 上面的协议，目前只能实现正确的断句效果，但是RPC还需要记录序列化的方式，便于服务提供方将二进制数据反序列化，还原正确的语义。所以**我们需要将序列化方式拿出，类似协议长度一样用固定长度记录**。
>
> 我们刚才说到服务提供方可能收到很多二进制数据，而这些二进制数据可以根据协议长度划分成多个请求处理，服务提供方处理完成后，将处理结果返回。请求方怎么去识别返回结果是属于那个请求的呢？我们可以在发送请求时生成一个消息ID,并将这个消息ID伴随请求一起发送给服务提供方，在服务提供方返回结果时带上消息ID。这样请求方就可以绑定请求与响应的关系。所以**我们需要将消息ID,类似协议长度一样用固定长度记录**。
>
> 这种需要固定长度存放的参数，我们可以统称为“协议头”，这样整个协议被拆分为**协议头**和**协议体**。在协议头里面，我们除了存放协议长度、序列化方式、消息ID，还会存放协议标示、消息类型等参数。而协议体一般只放请求接口方法、请求参数和一些扩展属性，具体协议如下图所示：
>
> ![image-20220813180330233](https://s2.loli.net/2022/08/14/HyhY5Jg1tiCMa7k.png)

### 可扩展RPC协议

> 上面的定长协议基本成型，但是当我们有些应用交互需要向协议头里面添加新的参数，怎么办呢？
>
> 如果只对这些应用添加参数升级，对于没有升级的应用而言，解析协议头和协议体都会出现错误，导致线上兼容问题。只能所有系统全面升级，强耦合，不利于系统的扩展性和健壮性。
>
> 将新增的参数放到协议体？这种方式是可行的，但是协议体的内容都是需要经过反序列化获取的，所以每次我们想要获取这些参数时，都要先反序列化。在某些场景下，会加重CPU的消耗，不推荐。
>
> 回头想想，我们在设计不定长协议的思路，我们通过一个固定长度位置存放协议体长度，那么我们为什么不用一个固定长度位置存放协议头长度呢！ 整体协议变成三部分内容：**固定部分**、**协议头内容**、**协议体内容**。具体协议如下：![image-20220813204351622](https://s2.loli.net/2022/08/14/EVTz3NdnH4WMbG2.png)

# 三、序列化：对象怎么在网络中传输？

> 在不同的场景下合理地选择序列化方式，对提升 RPC 框架整体的稳定性和性能是至关重要的。

## 为什么需要序列化

> 网络传输的数据必须是二进制数据，但是调用方请求的参数都是对象。对象是不能直接在网络中传输的，所以我们需要提前把它转成可传输的二进制数据。这个过程我们一般叫做**序列化**。序列化过程可以分为**请求方序列化**和**服务调用方反序列化**。
>
> ![](https://s2.loli.net/2022/08/14/uAvdaRK2UZSPsYj.png)

## 有哪些常用的序列化方式？

### JDK原生序列化

>```java
>package com.gjk.javabasis.serialization;
>
>import java.io.FileInputStream;
>import java.io.FileOutputStream;
>import java.io.IOException;
>import java.io.ObjectInputStream;
>import java.io.ObjectOutputStream;
>import java.io.Serializable;
>
>/**
> * Student
> *
> * @author: GJK
> * @date: 2022/8/14 17:52
> * @description:
> */
>public class Student implements Serializable {
>
>    private int no;
>
>    private String name;
>
>    public int getNo() {
>        return no;
>    }
>
>    public String getName() {
>        return name;
>    }
>
>    public void setNo(int no) {
>        this.no = no;
>    }
>
>    public void setName(String name) {
>        this.name = name;
>    }
>
>    @Override
>    public String toString() {
>        return "Student{" +
>                "no=" + no +
>                ", name='" + name + '\'' +
>                '}';
>    }
>
>
>    public static void main(String[] args) throws IOException, ClassNotFoundException {
>        String basePath  = "C:\\Users\\Administrator\\Desktop\\";
>        Student student = new Student();
>        student.setName("gjk");
>        student.setNo(99);
>        //序列化
>        FileOutputStream fileOutputStream = new FileOutputStream((basePath + "student.dat"));
>        ObjectOutputStream objectOutputStream = new ObjectOutputStream(fileOutputStream);
>        objectOutputStream.writeObject(student);
>        objectOutputStream.flush();
>        objectOutputStream.close();
>
>        //反序列化
>        FileInputStream fileInputStream = new FileInputStream((basePath + "student.dat"));
>        ObjectInputStream objectInputStream = new ObjectInputStream(fileInputStream);
>        Student newStudent = (Student) objectInputStream.readObject();
>        System.out.println(newStudent.toString());
>    }
>}
>
>```
>
>上面的代码就是JDK提供的机制，通过ObjectOutputStream实现序列化，通过ObjectInputStream实现反序列化。

### JSON

> JSON进行序列化存在的问题：
>
> * JSON进行序列化的额外空间开销比较大，对于大数据量服务意味着需要巨大的内存和磁盘开销。
> * JSON没有类型，像Java语言需要通过反射统一解决，所有性能不会太好。
>
> 所以如果使用JSON序列化，调用方和服务提供方之间传输的数据量要小，否则严重影响性能。

### Hessian

> Hessian是动态类型、二进制、紧凑的，并且可跨语言移植的一种序列化框架。Hessian协议要比JDK、JSON更加紧凑，性能上要比JDK、JSON序列化更高效，而且生产的字节数更小。
>
> ```java
>     public void HessianSerializable(Student student) throws IOException, ClassNotFoundException {
>         //序列化
>         ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
>         Hessian2Output hessian2Output = new Hessian2Output(byteArrayOutputStream);
>         hessian2Output.writeObject(student);
>         hessian2Output.flushBuffer();
>         byte[] bytes = byteArrayOutputStream.toByteArray();
>         byteArrayOutputStream.close();
> 
>         //反序列化
>         ByteArrayInputStream byteArrayInputStream = new ByteArrayInputStream(bytes);
>         Hessian2Input hessian2Input = new Hessian2Input(byteArrayInputStream);
>         Student newStudent = (Student) hessian2Input.readObject();
>         hessian2Input.close();
>         System.out.println(newStudent.toString());
>     }
> ```
>
> 相对于JDK、JSON,由于Hessian更加高效，生成的字节数更小，有非常好的兼容性和稳定性，所以Hessian更加适合作为RPC框架远程通信的序列化协议。但是Hessian本身也存在对Java部分对象类型不支持，比如：
>
> * linked系列，LinkedHashMap、LinkedHashSet等，但是可以通过CollectionDeserializer 类修复；
>
> * Locale 类，可以通过扩展 ContextSerializerFactory 类修复；
>
> * Byte/Short 反序列化的时候变成 Integer
>
>   

## RPC框架中如何选择序列化方式

> 选择序列化方式，我可以参考一下几个方面：
>
> * **性能和效率**。序列化是RPC调用的一个必须过程，序列化的性能和效率直接关系到RPC框架的性能和效率
> * **空间开销**。序列化后的二进制数据越小，网络传输的数据量就越小，传输数据速度就越快。RPC是远程调用，那么网络传输的速度直接关系到请求响应的耗时。
> * **序列化协议的通用性和兼容性**。与序列化协议的效率、性能、序列化协议后的体积相比，其通用性和兼容性的优先级会更高，因为他是会直接关系到服务调用的稳定性和可用率的，对于服务的性能来说，服务的可靠性显然更加重要。
> * **序列化协议的安全性**。以 JDK 原生序列化为例，它就存在漏洞。如果序列化存在安全漏洞，那么线上的服务就很可能被入侵。
>
> 以上参考因素优先级如下：
>
> ![202208141854893.png](https://s2.loli.net/2022/08/14/DwWhT9SQ8fXEcO7.png)
>
> 综上所述，我们首选的还是Hessian序列化方式，因为它在性能、时间、空间、通用性、兼容性和安全性都满足我们的要求。

## RPC框架在使用时注意哪些问题

> 序列化问题，除了RPC框架本身的问题，大多数问题都是使用方使用不正确导致的。下面盘点人为高频问题：
>
> * **对象构造得过于复杂**
> * **对象过于庞大**
> * **使用序列化框架不支持的类作为入参类**
> * **对象有复杂的继承关系**
>
> 在使用 RPC 框架的过程中，我们构造入参、返回值对象，主要记住以下几点：
>
> * 1、对象要尽量简单，没有太多的依赖关系，属性不要太多，尽量高内聚；
> * 2、 入参对象与返回值对象体积不要太大，更不要传太大的集合
> * 3、尽量使用简单的、常用的、开发语言原生的对象，尤其是集合类；
> * 4、对象不要有复杂的继承关系，最好不要有父子类的情况。




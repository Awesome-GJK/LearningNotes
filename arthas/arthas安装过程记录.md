## 背景

> Arthas 是一款线上监控诊断产品，通过全局视角实时查看应用 load、内存、gc、线程的状态信息，并能在不修改应用代码的情况下，对业务问题进行诊断，包括查看方法调用的出入参、异常，监测方法执行耗时，类加载信息等，大大提升线上问题排查效率。
>
> 我一直想学习如何使用Arthas，并且最近在写代码涉及性能这一块，总不能一直`System.currentTimeMillis()`，那也太low了。所以借着这个机会，刚好学习一下Arthas。

首先，我找了集介绍、安装、使用于一身的[官网Arthas文档](https://arthas.aliyun.com/doc/)。

## 下载jar包

先跟着文档走，我开始下载`Arthas.jar`包,命令如下：

```sh
curl -O https://arthas.aliyun.com/arthas-boot.jar
```

但是仅仅是下载jar包，我就遇到了问题，首选我实在`idea`中使用`Terminial`窗口执行下载命令下载的。执行命令后`Terminial`窗口并没有下载jar包，而是提示如下信息。

![image-20221212133107077](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130928357.png)

头疼！我上网搜了一番，都不存在有人下载失败，并且我直接通过访问`https://arthas.aliyun.com/arthas-boot.jar`链接，也可以下载 jar 包，那就不存在网络问题了。

然后我通过 cmd 进入命令行，再次执行下载 jar 包的命令，成功下载。

![image-20221212133729876](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130928295.png)

都是命令行，这两者有什么区别呢？说实话我是想不通，研究了半天，网上各种找帖子。最后我发现 idea 的`Terminial`窗口是 PowerShell 提供的命令行窗口，而 cmd 是 windows 自带的命令行窗口。

## 启动jar包

既然可以下载，我暂时没有去深究为什么 PowerShell 提供的命令行窗口无法下载的问题，咱们还是先跑主线吧，支线暂时不管了。

继续跟着官网文档走，我们开始执行启动命令。

```sh
java -jar arthas-boot.jar
```

头又疼了！怎么执行个启动命令也能错呢？Why allways me? 我们先来看看，错误提示。

![image-20221212134954985](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130929466.png)

提示中有这么一句话*Try to run 'jps' commond lists the instrumented Java HotSpot VMs on the target system.*这句话中提到了 `jps`命令，首先我们得知道 **jps 是用来查看 Java 进程的，等同于 ps -ef | grep java **，它是jdk自带的命令，是我们安装jdk是就会带有命令。然后我单独执行`jps`显示没有 Java 进程，然而我本地起着`eureka`和好几个 idea 窗口呢，怎么可能没有 Java 进程呢！不会我 jdk 安装的有问题吧。

网上搜了一下`jps`执行无效的原因，[找到了这样的一个帖子](https://blog.csdn.net/qq_43413788/article/details/107772563)，帮助我解决的问题。

> 原因：在 Windows系统中，每个 java 进程启动之后都在 **%TMP%/hsperfdata_${user}** (${user}为当前登录用户名) 目录下建立一个以该 java 进程 pid 为文件名的文件，用以记录该 java 进程的一些信息。 通常是因为没有对这个文件的写入权限而导致jps命令查看不到进程。
>
> * 通过环境变量查看`%TMP%`位置![image-20221212140451236](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130929264.png)
> * 进入目录找到`%TMP%/hsperfdata_${user}`![image-20221212140556970](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130930619.png)
> * 查看属性-安全。发现没有配置当前用户的权限
> * ![image-20221212140711578](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130930593.png)
> * 点击编辑，添加角色![image-20221212140933308](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130930629.png)
> * 点击完全控制后，应用-确定保存即可。![image-20221212141338325](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130930930.png)

这个时候，进入当前用户的目录中，我们可以看到以pid命名的文件，并且`jsp`命令也可以有效执行

![image-20221212141753281](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130930396.png)

## 选择需要织入的java进程

既然问题解决了，那咱们继续执行命令吧。此时我们可以获取所有的 Java 进程id

![image-20221212160556005](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130930802.png)

`marketCenterServer`进程是第 1 个，则输入 1，再输入`回车/enter`。Arthas 会 attach 到目标进程上，并输出日志：

![image-20221212160655140](https://raw.githubusercontent.com/GJKGJKGJK/MyImageBed/master/typora_imgs/202212130930560.png)

到此，Arthas 已经织入到我们的代码中，只要在命令窗口输入命令接口执行相应功能。

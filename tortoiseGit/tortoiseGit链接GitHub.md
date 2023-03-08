## 1、tortoiseGit安装

> 略

## 2、github创建访问令牌

> 首先我们需要在`github`上创建访问令牌`access tokens`，步骤如下
>
> 1. 选择`setting` ![image-20230308165302654](F:\MySpace\Awesome_GJK\LearningNotes\tortoiseGit\images\tortoiseGit链接GitHub\image-20230308165302654.png)
>
>    
>
> 2. 选择` Developer settings`![image-20230308170048945](F:\MySpace\Awesome_GJK\LearningNotes\tortoiseGit\images\tortoiseGit链接GitHub\image-20230308170048945.png)
>
> 3. 选择`Tokens(classic) ` -> `Generate new token `![image-20230308170410221](F:\MySpace\Awesome_GJK\LearningNotes\tortoiseGit\images\tortoiseGit链接GitHub\image-20230308170410221.png)
>
> 4. *Note*  最好用来记录这个token的用处，*Expiration *可以设置token的有效益，根据token使用情况而定，个人建议永久。*Select scopes* 是用来设置这个token的权限，一般选择 *repo* 即可。![image-20230308171030102](F:\MySpace\Awesome_GJK\LearningNotes\tortoiseGit\images\tortoiseGit链接GitHub\image-20230308171030102.png)
>
> 5. 点击 *Generate token*。![image-20230308171156676](F:\MySpace\Awesome_GJK\LearningNotes\tortoiseGit\images\tortoiseGit链接GitHub\image-20230308171156676.png)
>
> 6. 生成后的token只会展示一次，后面我们就无法查看。此时我们复制token，并单独保存，或者下次再生成也行。![image-20230308171324935](F:\MySpace\Awesome_GJK\LearningNotes\tortoiseGit\images\tortoiseGit链接GitHub\image-20230308171324935.png)

## 3、tortoiseGit配置github访问权限

> 进入`tortoiseGit` 的设置页面，选择`Git`->`远端`->`origin` ,复制`URL`粘贴到`推送URL`,并且将刚刚在github生成的`token`粘贴到`推送URL`中，参考下面的格式：
>
> * URL为Token+GitHub项目地址，即https://40位token@项目地址，例如https://ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx@github.com/Awesome-GJK/LearningCodes.git
>
> ![image-20230308171704724](F:\MySpace\Awesome_GJK\LearningNotes\tortoiseGit\images\tortoiseGit链接GitHub\image-20230308171704724.png)
>
> 现在我们就可以正常推送代码到github了！！！
>
> 注意哦！推送代码时`自动加载Putty秘钥`是不能勾上的！！！
>
> ![image-20230308172459209](F:\MySpace\Awesome_GJK\LearningNotes\tortoiseGit\images\tortoiseGit链接GitHub\image-20230308172459209.png)




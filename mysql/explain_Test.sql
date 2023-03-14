#explain关键字各字段介绍：
		#id 在一个大的查询语句中每个SELECT关键字都对应一个唯一的id
		#select_type SELECT关键字对应的那个查询的类型
		#table 表名
		#partitions 匹配的分区信息
		#type 针对单表的访问方法
		#possible_keys 可能用到的索引
		#key 实际上使用的索引
		#key_len 实际使用到的索引长度
		#ref 当使用索引列等值查询时，与索引列进行等值匹配的对象信息
		#rows 预估的需要读取的记录条数
		#filtered 某个表经过搜索条件过滤后剩余记录条数的百分比
		#Extra 一些额外的信息

################################################################################################################

#性能按type排序
#system > const > eq_ref > ref > ref_or_null > index_merge > unique_subquery > index_subquery > range > index > ALL

#性能按Extra从高到低排序
#Using index：用了覆盖索引
#Using index condition：用了条件索引（索引下推）
#Using where：从索引查出来数据后继续用where条件过滤
#Using join buffer (Block Nested Loop)：join的时候利用了join buffer（优化策略：去除外连接、增大join buffer大小）
#Using filesort：用了文件排序，排序的时候没有用到索引
#Using temporary：用了临时表（优化策略：增加条件以减少结果集、增加索引，思路就是要么减
#Start temporary, End temporary：子查询的时候，可以优化成半连接，但是使用的是通过临时表来去重
#FirstMatch(tbl_name)：子查询的时候，可以优化成半连接，但是使用的是直接进行数据比较来去重


#常见的优化sql手段：
#1. SQL语句中IN包含的值不应过多，不能超过200个，200个以内查询优化器计算成本时比较精准，超过个是估算的成本，另外建议能用between就不要用in，这样就可以使用range索引了。
#2. SELECT语句务必指明字段名称：SELECT * 增加很多不必要的消耗（cpu、io、内存、网络带宽）；了使用覆盖索引的可能性；当表结构发生改变时，前断也需要更新。所以要求直接在select后面接上字名。
#3. 当只需要一条数据的时候，使用limit 1
#4. 排序时注意是否能用到索引
#5. 使用or时如果没有用到索引，可以改为union all 或者union
#6. 如果in不能用到索引，可以改成exists看是否能用到索引
#7. 使用合理的分页方式以提高分页的效率
#8. 不建议使用%前缀模糊查询
#9. 避免在where子句中对字段进行表达式操作
#10. 避免隐式类型转换
#11. 对于联合索引来说，要遵守最左前缀法则
#12. 必要时可以使用force index来强制查询走某个索引
#13. 对于联合索引来说，如果存在范围查询，比如between,>,<等条件时，会造成后面的索引字段失效。
#14. 尽量使用inner join，避免left join，让查询优化器来自动选择小表作为驱动表
#15. 必要时刻可以使用straight_join来指定驱动表，前提条件是本身是inner join



################################################################################################################
#id

#查询语句中每出现一个SELECT关键字，不管from后面有多少张表，MySQL也只会为它们分配一个相同的id值。
explain select * from t1 join t2;

#对于子查询语句来说，就可能涉及多个SELECT关键字，所以子查询的执行计划中，每个SELECT关键字都会对应一个唯一的id值
explain select * from t1 where a in (select a from t2) or c = 'c';

#但是子查询可能会被查询优化器优化进行重写，从而转换为连接查询。
explain select * from t1 where a in (select a from t2);

#由于union会进行去重，所以在两个查询语句执行后，会创建临时表<union1,2>进行合并
explain select * from t1 union select * from t2;

#而union all不进行去重，所以不会创建临时表
explain select * from t1 union all select * from t2;

################################################################################################################
#select_type 

#查询语句中不包含UNION或者子查询的查询都算作是SIMPLE类型。
explain select * from t1;

#连接查询也算是SIMPLE类型
explain select * from t1 join t2;

#对于包含UNION、UNION ALL或者子查询的大查询来说，它是由几个小查询组成的，其中最左边的那个查询的select_type值就是PRIMARY
explain select * from t1 where a in (select a from t2) or c = 'c';

#对于包含UNION或者UNION ALL的大查询来说，它是由几个小查询组成的，其中除了最左边的那个小查询以外，其余的小查询的select_type值就是UNION。
#MySQL选择使用临时表来完成UNION查询的去重工作，针对该临时表的查询的select_type就是UNIONRESULT
explain select * from t1 union select * from t2;

#SUBQUERY为非相关子查询，代表子查询由于会被物化，所以只需要执行一遍
explain select * from t1 where a in (select a from t2) or c = 'c';

#DEPENDENT SUBQUERY为相关子查询，代表此查询可能会被执行多次
explain select * from t1 where a in (select a from t2 where t1.a = t2.a) or c ='c';

#select_type是DERIVED，说明该子查询是以物化的方式执行的。
#id为1的记录代表外层查询，大家注意看它的table列显示的是<derived2>，表示该查询是在select_type为DERIVED派生表物化后进行查询的。
explain select * from (select a, count(*) from t2 group by a ) as deliver1;

#当查询优化器在执行包含子查询的语句时，选择将子查询物化之后与外层查询进行连接查询时，该子查询对应的select_type属性就是MATERIALIZED。
explain select * from t1 where a in (select c from t2 where e = 1);

################################################################################################################
#type

#当表中只有一条记录并且该表使用的存储引擎的统计数据是精确的，比如MyISAM、Memory，那么对该表的访问方法就是system
explain select * from t3;

#当我们根据主键或者唯一二级索引列与常数进行等值匹配时，对单表的访问方法就是const。
explain select * from t1 where a = 1;

#在连接查询时，如果被驱动表是通过主键或者唯一二级索引列等值匹配的方式进行访问的（如果该主键或者唯一二级索引是联合索引的话，所有的索引列都必须进行等值比较），则对该被驱动表的访问方法就是eq_ref
explain select * from t1 join t2 on t1.a = t2.a;

#当通过普通的二级索引列与常量进行等值匹配时来查询某个表，那么对该表的访问方法就可能是ref
explain select * from t1 where b = 1;

#当对普通二级索引进行等值匹配查询，该索引列的值也可以是NULL值时，那么对该表的访问方法就可能是ref_or_null
explain select * from t1 where b = 1 or b is null;

#当使用两个索引，且各个索引查出的记录无需经过其他索引筛选时，那么对该表的访问方法就可能是index_merge
explain select * from t1 where a = 1 or b = 1;

#如果查询优化器决定将IN子查询转换为EXISTS子查询，而且子查询可以使用到主键进行等值匹配的话，那么该子查询执行计划的type列的值就是unique_subquery
#in子查询转成exists子查询：select * from t1 where EXISTS(select a from t2 where t1.e = t2.e and t1.c = t2.a) or a =1;
explain select * from t1 where c in (select a from t2 where t1.e = t2.e) or a =1;

#index_subquery与unique_subquery类似，只不过访问子查询中的表时使用的是普通的索引
explain select * from t1 where c in (select b from t2 where t1.e = t2.e) or a =1;

#范围查询时，type列值就是range
explain select * from t1 where a > 1;
explain select * from t1 where a in (1,2,3);

#当我们可以使用覆盖索引，但需要扫描全部的索引记录时，该表的访问方法就是index。
explain select b from t1;

#当不走索引，全部扫描时，type列值就是All
explain select b from t1 where e ='a';

################################################################################################################
#ref 当使用索引列等值匹配的条件去执行查询时，也就是在访问方法是const、eq_ref、ref、ref_or_null、unique_subquery、index_subquery其中之一时，ref列展示的就是与索引列作等值匹配的东西是什么，比如只是一个常数或者是某个列。

#当等值匹配时，以常数与索引列匹配，那么ref的值为const
explain select b from t1 where b = 1;

#当等值匹配时，以某一列与索引列匹配，那么ref的值为具体模式.表.列名
explain select * from t1 where a in (select a from t2);

################################################################################################################
#Extra 用来说明一些额外信息的，我们可以通过这些额外信息来更准确的理解MySQL到底将如何执行给定的查询语句。

#当查询语句的没有FROM子句时将会提示该额外信息,那么Extra的值为No tables used
explain select 1;

#查询语句的WHERE子句永远为FALSE时将会提示该额外信息，那么Extra的值为Impossible WHERE
explain select b from t1 where 1=0;

#当查询使用MIN或者MAX聚集函数，但是并没有符合WHERE条件的记录时，那么Extra的值为No matching min/max row
explain select max(a) from t1 where a=100;

#当我们的查询列表以及搜索条件中只包含属于某个索引的列，也就是在可以使用索引覆盖的情况下，那么Extra的值为Using index
explain select d from t1 where b =1;

#有些搜索条件中虽然出现了索引列，但却不能使用到索引,那么Extra的值为Using index condition
explain select * from t1 where b =1 and b like '%1';

#当我们使用全表扫描来执行对某个表的查询，并且该语句的WHERE子句中有针对该表的搜索条件时，那么Extra的值为Using where
explain select * from t1 where e = 1;

#在连接查询执行过程中，当被驱动表不能有效的利用索引加快访问速度，MySQL一般会为其分配一块名叫joinbuffer的内存块来加快查询速度。那么Extra的值为 Using join buffer 
explain select * from t1 join t2 on t1.e = t2.e;

#排序时，无法使用索引，只能在内存(少量数据)或者磁盘(大量数据)中进行排序，那么Extra的值为Using filesort
explain select * from t1 order by e;

#未使用索引，只能借助临时表来完成一些功能，比如去重、排序之类的，那么Extra的值为Using filesort
explain select e, count(1) from t1 group by e;
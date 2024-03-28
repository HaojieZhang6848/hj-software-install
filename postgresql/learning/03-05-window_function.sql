-- 创建表 empsalary
CREATE TABLE empsalary
(
    depname VARCHAR(50),
    empno   INT,
    salary  DECIMAL(10, 2)
);

-- 插入一些实际数据
INSERT INTO empsalary (depname, empno, salary)
VALUES ('HR', 101, 50000.00),
       ('HR', 102, 52000.00),
       ('HR', 103, 48000.00),
       ('HR', 104, 52000.00),
       ('IT', 201, 60000.00),
       ('IT', 202, 55000.00),
       ('IT', 203, 58000.00),
       ('IT', 204, 62000.00),
       ('Sales', 301, 45000.00),
       ('Sales', 302, 47000.00),
       ('Sales', 303, 49000.00);

-- 使用窗口函数
select es.depname,
       es.empno,
       es.salary,
       rank() over (order by es.salary desc) as salary_rank
from empsalary es;

-- 使用窗口函数
select es.depname,
       es.empno,
       avg(es.salary) over (partition by es.depname) as avg_salary_in_dep,
       min(es.salary) over (partition by es.depname) as min_salary_in_dep,
       max(es.salary) over (partition by es.depname) as max_salary_in_dep,
       rank() over (partition by es.depname order by es.salary desc) as salary_rank_in_dep
from empsalary es;

-- 因为没有使用group by，所以window frame就是整个分组
-- 这里因为也没有partition by，所以整个表就是一个分组
select salary,
       sum(salary) over () as sum_salary
from empsalary;

-- 使用order by了以后，window frame就是当前行之前的所有行，以及当前行之后与order by表达式相等的行
select salary,
       sum(salary) over (order by salary) as sum_salary
from empsalary;
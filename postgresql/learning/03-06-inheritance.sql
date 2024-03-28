-- 繼承功能比較嚴格的限制是索引（包含唯一性索引），還有外部鍵的限制條件，都只能用在單一資料表，而不會衍生至他們的子資料表中。對外部鍵來說，無論引用資料表或是參考資料表的情況都一樣。下面是一些例子說明：
--
-- 如果我們宣告 cities.name 具備唯一性或是主鍵，這不會限制到 capitals 中有重覆的項目。而這些重覆的資料列就會出現在 cities 的查詢結果中。事實上，預設的 capitals 就沒有唯一性的限制，所以就可能有多個資料列記載相同的名稱。你可以在 capitals 中也加入唯一性索引，但這也無法避免 capitals 和 cities 中有重覆的項目。
--
-- 同樣地，如果我們指定 cities.name 以外部鍵的方式，參考另一個資料表，而這個外部鍵也不會衍生到 capitals 中。這種情況你就必須在 capitals 中也以 REFERENCES 設定同樣外部鍵的引用。
--
-- 如果有另一個資料表的欄位設定了 REFERENCES cities(name) 就會允許其他的資料表包含城市名稱，但就沒有首都名稱。在這個情況下，沒有好的解決辦法。
--
-- 這些缺點可能會在後續的版本中被修正，但在此時此刻，當你需要使用繼承功能讓你的應用設計更好用時，你就必須要同時考慮這些限制。
CREATE TABLE cities (
  name       text,
  population real,
  altitude   int     -- (in ft)
);

-- 创建一个继承自 cities 的表, capitals表中的数据会显示在cities表中
CREATE TABLE capitals (
  state      char(2)
) INHERITS (cities);

-- 插入一些城市数据
INSERT INTO cities (name, population, altitude) VALUES
('New York City', 8398748, 33),
('Los Angeles', 3990456, 285),
('Chicago', 2705994, 594),
('Houston', 2325502, 80),
('Phoenix', 1680992, 1132),
('Philadelphia', 1584064, 39),
('San Antonio', 1547253, 650),
('San Diego', 1425976, 72),
('Dallas', 1345047, 430),
('San Jose', 1030119, 82);

-- 插入一些首府数据
INSERT INTO capitals (name, population, altitude, state) VALUES
('Sacramento', 508529, 30, 'CA'),
('Austin', 978908, 489, 'TX'),
('Boston', 694583, 141, 'MA'),
('Denver', 716492, 5280, 'CO'),
('Hartford', 122587, 59, 'CT');

-- 选择所有的城市数据（包括首府）
SELECT * FROM cities;

-- 选择所有的首府数据
SELECT * FROM capitals;

-- 选择所有的城市数据（不包括首府）
SELECT * FROM ONLY cities;
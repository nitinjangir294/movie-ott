-- Movie and OTT Content Analysis | Course: Data Analytics | 25CAH-727
-- Target dialect: MySQL 8.0+
-- Dataset provided is synthetic for academic demonstration.
-- Import movie_ott_dataset.csv into a staging table, then run the queries below.

CREATE DATABASE IF NOT EXISTS ott_analytics;
USE ott_analytics;

DROP TABLE IF EXISTS ott_content;
CREATE TABLE ott_content (
    show_id VARCHAR(12) PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    content_type VARCHAR(20) NOT NULL,
    director VARCHAR(120),
    country VARCHAR(100),
    release_year SMALLINT,
    date_added DATE,
    rating VARCHAR(20),
    genre VARCHAR(60),
    duration VARCHAR(30),
    listed_in VARCHAR(200),
    description TEXT,
    CHECK (content_type IN ('Movie', 'TV Show')),
    CHECK (release_year BETWEEN 1900 AND 2100 OR release_year IS NULL)
);

-- Option A: use MySQL Workbench Table Data Import Wizard to import CSV into ott_content.
-- Option B: after enabling local_infile and confirming file path:
-- LOAD DATA LOCAL INFILE '/absolute/path/movie_ott_dataset.csv'
-- INTO TABLE ott_content
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\\n' IGNORE 1 ROWS
-- (show_id,title,content_type,director,country,release_year,@date_added,rating,genre,duration,listed_in,description)
-- SET date_added = NULLIF(@date_added, '');

-- 1. Basic validation
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT show_id) AS unique_ids
FROM ott_content;

SELECT content_type, COUNT(*) AS title_count
FROM ott_content
GROUP BY content_type
ORDER BY title_count DESC;

-- 2. Missing-value profile
SELECT
  SUM(director IS NULL OR TRIM(director) = '') AS missing_director,
  SUM(country IS NULL OR TRIM(country) = '') AS missing_country,
  SUM(rating IS NULL OR TRIM(rating) = '') AS missing_rating
FROM ott_content;

-- 3. Genre analysis
SELECT genre, COUNT(*) AS title_count,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM ott_content), 2) AS pct_of_catalog
FROM ott_content
GROUP BY genre
ORDER BY title_count DESC;

-- 4. Annual release trend
SELECT release_year, content_type, COUNT(*) AS title_count
FROM ott_content
WHERE release_year IS NOT NULL
GROUP BY release_year, content_type
ORDER BY release_year, content_type;

-- 5. Country analysis, with nulls grouped as Unknown
SELECT COALESCE(country, 'Unknown') AS country_name, COUNT(*) AS title_count
FROM ott_content
GROUP BY COALESCE(country, 'Unknown')
ORDER BY title_count DESC
LIMIT 10;

-- 6. CTE: yearly growth in catalog records (record count by release year)
WITH yearly AS (
  SELECT release_year, COUNT(*) AS title_count
  FROM ott_content
  WHERE release_year IS NOT NULL
  GROUP BY release_year
),
with_previous AS (
  SELECT release_year, title_count,
         LAG(title_count) OVER (ORDER BY release_year) AS previous_year_count
  FROM yearly
)
SELECT release_year, title_count, previous_year_count,
       title_count - previous_year_count AS change_vs_previous_year
FROM with_previous
ORDER BY release_year;

-- 7. Window function: rank genres by title count
WITH genre_counts AS (
  SELECT genre, COUNT(*) AS title_count
  FROM ott_content
  GROUP BY genre
)
SELECT genre, title_count,
       DENSE_RANK() OVER (ORDER BY title_count DESC) AS genre_rank
FROM genre_counts
ORDER BY genre_rank, genre;

-- 8. Top 3 genres within each content type (CTE + window function)
WITH type_genre AS (
  SELECT content_type, genre, COUNT(*) AS title_count
  FROM ott_content
  GROUP BY content_type, genre
),
ranked AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY content_type ORDER BY title_count DESC, genre
  ) AS rn
  FROM type_genre
)
SELECT content_type, genre, title_count
FROM ranked
WHERE rn <= 3
ORDER BY content_type, rn;

-- 9. Conditional aggregation: rating distribution by type
SELECT rating,
       SUM(content_type = 'Movie') AS movie_count,
       SUM(content_type = 'TV Show') AS tv_show_count,
       COUNT(*) AS total_count
FROM ott_content
GROUP BY rating
ORDER BY total_count DESC;

-- 10. Self-contained business view
CREATE OR REPLACE VIEW vw_ott_kpis AS
SELECT
  COUNT(*) AS total_titles,
  SUM(content_type = 'Movie') AS movies,
  SUM(content_type = 'TV Show') AS tv_shows,
  COUNT(DISTINCT country) AS distinct_countries,
  COUNT(DISTINCT genre) AS distinct_genres,
  MIN(release_year) AS first_release_year,
  MAX(release_year) AS latest_release_year
FROM ott_content;

SELECT * FROM vw_ott_kpis;

-- 11. Subquery: titles released after the catalog's average release year
SELECT show_id, title, content_type, release_year, genre
FROM ott_content
WHERE release_year > (SELECT AVG(release_year) FROM ott_content)
ORDER BY release_year DESC;

-- 12. Set operator example (MySQL 8.0 supports UNION; INTERSECT/EXCEPT depend on version)
SELECT title, content_type FROM ott_content WHERE genre = 'Drama'
UNION
SELECT title, content_type FROM ott_content WHERE genre = 'Thriller';

-- 13. Example join using a normalized genre dimension
CREATE TABLE IF NOT EXISTS dim_genre (
  genre_id INT AUTO_INCREMENT PRIMARY KEY,
  genre_name VARCHAR(60) UNIQUE NOT NULL
);
INSERT IGNORE INTO dim_genre (genre_name)
SELECT DISTINCT genre FROM ott_content WHERE genre IS NOT NULL;

SELECT g.genre_name, COUNT(c.show_id) AS title_count
FROM dim_genre g
LEFT JOIN ott_content c ON c.genre = g.genre_name
GROUP BY g.genre_id, g.genre_name
ORDER BY title_count DESC;

-- 14. Example data quality check for duplicate titles (not necessarily duplicate records)
SELECT title, release_year, COUNT(*) AS occurrences
FROM ott_content
GROUP BY title, release_year
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;

-- 15. Export query results using MySQL Workbench result grid export for Tableau.

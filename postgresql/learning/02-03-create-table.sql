CREATE TABLE IF NOT EXISTS weather (
    id SERIAL PRIMARY KEY,
    city VARCHAR(80),
    temp_lo INT,           -- low temperature
    temp_hi INT,           -- high temperature
    prcp REAL,             -- precipitation
    date DATE
);

CREATE TABLE IF NOT EXISTS cities (
    name VARCHAR(80) PRIMARY KEY,
    location POINT
);
CREATE DATABASE IF NOT EXISTS claims_health;
USE claims_health;

ALTER TABLE claim_data
ADD COLUMN id INT AUTO_INCREMENT PRIMARY KEY;

/* 1. Data Standardization */
-- Clean categorical fields (uppercase + trim spaces)
UPDATE claim_data
SET
	`Hospital Region` = UPPER(TRIM(`Hospital Region`)),
    `Hospital Classification` = UPPER(TRIM(`Hospital Classification`)),
    `Hospital Sector` = UPPER(TRIM(`Hospital Sector`)),
    `Claim Status` = UPPER(TRIM(`Claim Status`)),
    `Hospital Province` = UPPER(TRIM(`Hospital Province`)),
    `Hospital Municipality` = UPPER(TRIM(`Hospital Municipality`))
WHERE id IS NOT NULL;

/* 2. Fix Inconsistent Values */
-- Standardize Inconsistent Region Labels
UPDATE claim_data
SET `Hospital Region` = 'PHRO VI'
WHERE `Hospital Region` IN ('PHRO-6', 'PHRO VI ', 'PHRO6');

/* 3. Duplicate Detection */
SELECT
	`Received Refiled Year`,
    `Hospital Name`,
    `Hospital Region`,
    `Claim Status`,
    `Claims Count`,
    `Claims Amount`,
    COUNT(*) AS duplicate_count
FROM claim_data
GROUP BY
	`Received Refiled Year`,
    `Hospital Name`,
    `Hospital Region`,
    `Claim Status`,
    `Claims Count`,
    `Claims Amount`
HAVING COUNT(*) > 1;

/* 4. Flag Duplicates */
-- Add column to mark duplicates
ALTER TABLE claim_data
ADD COLUMN is_duplicate INT DEFAULT 0;

-- Mark duplicate Rows
UPDATE claim_data cd
JOIN (
	SELECT
		`Received Refiled Year`,
        `Hospital Name`,
        `Hospital Region`,
        `Claim Status`,
        `Claims Count`,
        `Claims Amount`
	FROM claim_data
    GROUP BY 
		`Received Refiled Year`,
        `Hospital Name`,
        `Hospital Region`,
        `Claim Status`,
        `Claims Count`,
        `Claims Amount`
	HAVING COUNT(*) > 1
) dup
ON cd.`Received Refiled Year` = dup.`Received Refiled Year`
AND cd.`Hospital Name` = dup.`Hospital Name`
AND cd.`Hospital Region` = dup.`Hospital Region`
AND cd.`Claim Status` = dup.`Claim Status`
AND cd.`Claims Count` = dup.`Claims Count`
AND cd.`Claims Amount` = dup.`Claims Amount`
SET cd.is_duplicate = 1;

/* 5. Data Type Verification */
ALTER TABLE claim_data
MODIFY `Received Refiled Year` INT;

ALTER TABLE claim_data
MODIFY `Claims Count` INT;

ALTER TABLE claim_data
MODIFY `Claims Amount` DOUBLE;

/* 6. Outlier Detection */
WITH ordered_data AS (
	SELECT
		`Claims Amount`,
        ROW_NUMBER() OVER (ORDER BY `Claims Amount`) AS row_num,
        COUNT(*) OVER () AS total_rows
	FROM claim_data
),

quartiles AS (
	SELECT
		MAX(CASE WHEN row_num = FLOOR(total_rows * 0.25) THEN `Claims Amount` END) AS Q1,
        MAX(CASE WHEN row_num = FLOOR(total_rows * 0.75) THEN `Claims Amount` END) AS Q3
	FROM ordered_data
)

SELECT cd.*
FROM claim_data cd
JOIN quartiles q
WHERE cd.`Claims Amount` < (q.Q1 - 1.5 * (q.Q3 - q.Q1))
OR cd.`Claims Amount` > (q.Q3 + 1.5 * (q.Q3 - q.Q1));

/* 7. Feature Engineering */
-- Total Claim Volume
SELECT
	`Hospital Region`,
    SUM(`Claims Count`) AS total_claims
FROM claim_data
GROUP BY `Hospital Region`;

-- Financial Volume
SELECT 
	`Received Refiled Year`,
    SUM(`Claims Amount`) AS total_amount
FROM claim_data
GROUP BY `Received Refiled Year`;

-- Claim Status Distribution
SELECT
	`Hospital Region`,
    `Claim Status`,
    SUM(`Claims Count`) * 100.0 /
    SUM(SUM(`Claims Count`)) OVER (PARTITION BY `Hospital Region`) AS percentage
FROM claim_data
GROUP BY `Hospital Region`, `Claim Status`;

-- Denial Rate
SELECT
	`Hospital Region`,
    SUM(CASE WHEN `Claim Status` = 'DENIED' THEN `Claims Count` ELSE 0 END) * 100.0 /
    SUM(`Claims Count`) AS denial_rate
FROM claim_data
GROUP BY `Hospital Region`;

-- RTH Rate
SELECT 
	`Hospital Region`,
    SUM(CASE WHEN `Claim Status` = 'RTH' THEN `Claims Count` ELSE 0 END) * 100.0 /
    SUM(`Claims Count`) AS rth_rate
FROM claim_data
GROUP BY `Hospital Region`;

-- Average Claim Amount
SELECT
	`Hospital Region`,
    SUM(`Claims Amount`) / SUM(`Claims Count`) AS avg_claim_amount
FROM claim_data
GROUP BY `Hospital Region`;
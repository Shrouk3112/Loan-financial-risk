
--1) Loan approval rate by education level?

SELECT
    EducationLevel,
    COUNT(*) AS TotalApplicants,
    SUM(CASE WHEN LoanApproved = 1 THEN 1 ELSE 0 END) AS Approved,
    ROUND(100.0 * SUM(CASE WHEN LoanApproved = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS ApprovalRatePct
FROM [dbo].[Loan_Financial_Risk]
GROUP BY EducationLevel
ORDER BY ApprovalRatePct DESC;
/* Insight: There's a clear positive correlation between education level and loan approval rate — 
Doctorate holders have the highest approval rate at 44.03%, while High School graduates have the lowest at just 14.44%, nearly a 3x gap.
Education level appears to be a strong direct factor in the approval decision*/

-- 2)Does classifying clients into risk categories show a difference in average interest rate? 

SELECT
    CASE
        WHEN RiskScore < 30 THEN 'Low Risk'
        WHEN RiskScore BETWEEN 30 AND 60 THEN 'Medium Risk'
        ELSE 'High Risk'
    END AS RiskCategory,
    COUNT(*) AS NumberOfClients,
    ROUND(AVG(InterestRate), 4) AS AvgInterestRate
FROM [dbo].[Loan_Financial_Risk]
GROUP BY
    CASE
        WHEN RiskScore < 30 THEN 'Low Risk'
        WHEN RiskScore BETWEEN 30 AND 60 THEN 'Medium Risk'
        ELSE 'High Risk'
    END
ORDER BY NumberOfClients DESC;
/* Insight: The vast majority of clients (18,289 out of 20,000) fall into the Medium Risk category,
while only 11 clients are classified as Low Risk. Average interest rate increases with risk level
(18.5% for Low Risk vs 24.74% for High Risk),
indicating the overall client base skews toward medium-to-high risk*/


-- 3) Do clients with previous loan defaults have a higher rejection rate?
SELECT
    PreviousLoanDefaults,
    COUNT(*) AS TotalClients,
    ROUND(100.0 * SUM(CASE WHEN LoanApproved = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS RejectionRatePct
FROM [dbo].[Loan_Financial_Risk]
GROUP BY PreviousLoanDefaults;
/*-- Insight: Clients with a history of previous loan defaults (PreviousLoanDefaults = 1)
have a higher rejection rate (84.46%) compared to those without any default history (75.17%) —
a gap of about 9 percentage points. Notably,
rejection rates are high across both groups, reflecting generally strict approval criteria overall*/



-- 4) Are clients with above-average monthly income more likely to get approved?

SELECT TOP 20 ApplicationDate, MonthlyIncome, CreditScore, LoanApproved
FROM [dbo].[Loan_Financial_Risk]
WHERE MonthlyIncome > (SELECT AVG(MonthlyIncome) FROM [dbo].[Loan_Financial_Risk])
ORDER BY MonthlyIncome DESC;
/*-- Insight: All 20 clients with above-average monthly income had their loans approved 
(100% approval rate), despite relatively low credit scores (471-658).
This suggests high income is a strong offsetting factor
in the approval decision, even when credit history is weak*/

-- 5) Does the debt-to-income ratio differ by loan purpose?

SELECT
    LoanPurpose,
    ROUND(AVG(DebtToIncomeRatio), 4) AS AvgDebtToIncome,
    ROUND(AVG(InterestRate), 4) AS AvgInterestRate
FROM [dbo].[Loan_Financial_Risk]
GROUP BY LoanPurpose
ORDER BY AvgDebtToIncome DESC;
/*-- Insight: Unlike other factors (such as income and education), LoanPurpose doesn't significantly 
affect the debt-to-income ratio or interest rate — all five purposes are very close
(less than 0.005 difference in ratio, and under 0.16% in interest rate). 
This suggests the company prices loans based on the client's own profile, not the purpose of the loan*/





-- 6) Who are the top 5 riskiest clients within each employment status?
WITH RankedRisk AS (
    SELECT
        ApplicationDate,
        EmploymentStatus,
        RiskScore,
        RANK() OVER (PARTITION BY EmploymentStatus ORDER BY RiskScore DESC) AS RiskRankWithinGroup
    FROM [dbo].[Loan_Financial_Risk]
)
SELECT *
FROM RankedRisk
WHERE RiskRankWithinGroup <= 5
ORDER BY EmploymentStatus, RiskRankWithinGroup;
/* Insight: Unemployed customers recorded the highest RiskScore overall (84),
while the highest value for Employed and Self-Employed was only 79 — this makes sense since lack of 
stable income increases the risk assessment.*/



-- 7) How does each client's net worth compare to their age group average?
WITH AgeGroups AS (
    SELECT *,
        CASE
            WHEN Age < 30 THEN 'Under 30'
            WHEN Age BETWEEN 30 AND 45 THEN '30-45'
            WHEN Age BETWEEN 46 AND 60 THEN '46-60'
            ELSE 'Above 60'
        END AS AgeGroup
    FROM [dbo].[Loan_Financial_Risk]
),
AgeGroupAvg AS (
    SELECT AgeGroup, AVG(NetWorth) AS AvgNetWorth
    FROM AgeGroups
    GROUP BY AgeGroup
)
SELECT TOP 20
    a.ApplicationDate,
    a.AgeGroup,
    a.NetWorth,
    g.AvgNetWorth,
    ROUND(a.NetWorth - g.AvgNetWorth, 2) AS DifferenceFromGroupAvg
FROM AgeGroups a
JOIN AgeGroupAvg g ON a.AgeGroup = g.AgeGroup
ORDER BY DifferenceFromGroupAvg DESC;
/*Insight: NetWorth ranges from 1,000 to 2,603,208 with an overall average of 72,294 —
a small number of clients (outliers) are significantly wealthier than their age group average, 
reflecting genuine wealth inequality in the data rather than a data entry error*/



-- 8) How has the monthly loan approval rate changed over time?

WITH MonthlyStats AS (
    SELECT
        FORMAT(ApplicationDate, 'yyyy-MM') AS ApplicationMonth,
        COUNT(*) AS TotalApplications,
        SUM(CASE WHEN LoanApproved = 1 THEN 1 ELSE 0 END) AS Approved
    FROM [dbo].[Loan_Financial_Risk]
    GROUP BY FORMAT(ApplicationDate, 'yyyy-MM')
)
SELECT
    ApplicationMonth,
    TotalApplications,
    Approved,
    ROUND(100.0 * Approved / TotalApplications, 2) AS ApprovalRatePct
FROM MonthlyStats
ORDER BY ApplicationMonth;
/*-- Insight: Monthly approval rates fluctuate significantly with no consistent trend —
ranging from under 11% (March 2019) to over 41% (November 2018), suggesting no clear seasonality in loan approval decisions. 
Also, the date range includes implausible far-future values,
indicating a data quality issue in the source data worth flagging*/



-- 9)Who are the top 5% riskiest clients in each education level, and were they approved?
WITH RiskPercentile AS (
    SELECT *,
        PERCENT_RANK() OVER (PARTITION BY EducationLevel ORDER BY RiskScore) AS RiskPct
    FROM [dbo].[Loan_Financial_Risk]
)
SELECT ApplicationDate, EducationLevel, RiskScore, LoanApproved
FROM RiskPercentile
WHERE RiskPct >= 0.95
ORDER BY EducationLevel, RiskScore DESC;
/*-- Insight: Out of 862 clients representing the top 5% riskiest within each education level, 
the overwhelming majority were rejected (LoanApproved = 0) — 
confirming RiskScore is a reliable and effective indicator in the loan approval decision*/


-- 10) Is there a relationship between credit score band and average interest rate?
WITH CreditBands AS (
    SELECT *,
        CASE
            WHEN CreditScore < 580 THEN 'Poor'
            WHEN CreditScore BETWEEN 580 AND 669 THEN 'Fair'
            WHEN CreditScore BETWEEN 670 AND 739 THEN 'Good'
            WHEN CreditScore BETWEEN 740 AND 799 THEN 'Very Good'
            ELSE 'Exceptional'
        END AS CreditBand
    FROM [dbo].[Loan_Financial_Risk]
)
SELECT
    CreditBand,
    ROUND(AVG(InterestRate), 4) AS AvgInterestRate,
    ROUND(AVG(RiskScore), 2) AS AvgRiskScore,
    COUNT(*) AS NumberOfClients
FROM CreditBands
GROUP BY CreditBand
ORDER BY AvgInterestRate DESC;
/* Insight: There's a clear inverse relationship between credit score and interest rate: 
Poor Credit clients (10,201 clients) pay an average rate of 25.85%, while Good Credit clients pay only 18.30% — a gap
of about 7.5 percentage points.
This confirms the system prices risk consistently and correctly based on credit score */


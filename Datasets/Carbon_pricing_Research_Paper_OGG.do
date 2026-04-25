********************************************************************************
* ECO 5435 - Economic Data Analysis
* Final Project: Do carbon taxes reduce CO2 emissions? Cross-country panel evidence
* Author: Preston Jarvis
* Date: April 2026
********************************************************************************

***********************************************************
* PART 0: SETUP
***********************************************************

clear all           // clears any data in memory
set more off        // stops Stata from pausing output
capture log close   // closes any open log file

* Set your working directory — change this to wherever your files are saved
cd "C:\Users\jarvisp\downloads"

* Open a log file to record all output (goes in your appendix)
log using "carbon_analysis_log.txt", text replace


********************************************************************************
* PART 1: LOAD AND CLEAN THE CO2 DATA (Our World in Data)
********************************************************************************

* Import the CSV file
import delimited "owid-co2-data.csv", clear

* Check what we loaded
describe
summarize

* Keep only the variables we need
keep country year co2_per_capita gdp population energy_per_gdp

* Drop observations before 1990 because the carbon pricing data only start at 1990
drop if year < 1990

* Drop regional aggregates and limit bias avoiding double counts and in general wierd trends created by frequency problems
drop if country == "World"
drop if strpos(country, "income")
drop if strpos(country, "Union")
drop if inlist(country, "Asia", "Europe", "Africa", "Oceania")
drop if inlist(country, "North America", "South America")

* Drop rows where CO2 per capita is missing (our outcome variable)
drop if co2_per_capita == .

* Create GDP per capita from total GDP and population
gen gdp_per_capita = gdp / population
label variable gdp_per_capita "GDP per capita (USD)"

* Label variables clearly
label variable co2_per_capita  "CO2 emissions per capita (tonnes)"
label variable energy_per_gdp  "Energy intensity (kWh per USD)"
label variable year             "Year"
label variable country          "Country name"

* Check the data looks right
list country year co2_per_capita gdp_per_capita in 500/520
codebook country year
*It looks perfect and even though the example I showed is the Bahamas which lack GDP I will remove it once we merge to not unnecessarily create more work for myself and shrink my dataset.

save "co2_clean.dta", replace


********************************************************************************
* PART 2: LOAD AND CLEAN THE CARBON PRICING DATA (World Bank Dashboard)
********************************************************************************

* The World Bank file is an Excel file with multiple sheets.
* We need the "Compliance_Price" sheet for prices and
* "Compliance_Gen Info" for country names.

* --- Step 2a: Load country name lookup from Gen Info sheet ---
import excel "data_08_2025.xlsx", sheet("Compliance_Gen Info") ///
    cellrange(A5) firstrow clear

* Keep only Unique ID and Jurisdiction (country name)
keep UniqueID Jurisdictioncovered
rename UniqueID     unique_id
rename Jurisdictioncovered country

* Clean up whitespace in country names
replace country = strtrim(country)

* Remove duplicates
duplicates drop unique_id, force

* Save lookup table
save "country_lookup.dta", replace


* --- Step 2b: Load carbon price data from Compliance_Price sheet ---
import excel "data_08_2025.xlsx", sheet("Compliance_Price") ///
    cellrange(A2) firstrow clear

* After import, the year columns will be named by their year value.
* Rename the Unique ID column to match our lookup
rename UniqueID unique_id

* Keep only Unique ID and the year columns (1990-2024)
* Drop non-year metadata columns
keep unique_id G H I J K L M N O P Q R S T U V W X Y Z ///
    AA AB AC AD AE AF AG AH AI AJ AK AL AM AN AO

* NOTE: If variable names come in differently, check with: describe
* Then rename manually to match. Example rename block below:
rename G  p1990
rename H  p1991
rename I  p1992
rename J  p1993
rename K  p1994
rename L  p1995
rename M  p1996
rename N  p1997
rename O  p1998
rename P  p1999
rename Q  p2000
rename R  p2001
rename S  p2002
rename T  p2003
rename U  p2004
rename V  p2005
rename W  p2006
rename X  p2007
rename Y  p2008
rename Z  p2009
rename AA p2010
rename AB p2011
rename AC p2012
rename AD p2013
rename AE p2014
rename AF p2015
rename AG p2016
rename AH p2017
rename AI p2018
rename AJ p2019
rename AK p2020
rename AL p2021
rename AM p2022
rename AN p2023
rename AO p2024

* Reshape from wide (one row per instrument) to long (one row per instrument-year)
reshape long p, i(unique_id) j(year)
rename p carbon_price

* Drop rows where no price is recorded (instrument not active that year)
drop if carbon_price == .

* Merge in country names
merge m:1 unique_id using "country_lookup.dta", keep(match master) nogenerate

* Drop known subnational jurisdictions as we are trying to keep it national
drop if inlist(country, "Alberta", "British Columbia", "California", ///
    "Quebec", "Ontario", "Saskatchewan", "Manitoba")
drop if inlist(country, "Beijing", "Shanghai", "Guangdong", "Chongqing", ///
    "Fujian", "Hubei", "Tianjin", "Shenzhen", "Shandong")
drop if inlist(country, "Baja California", "Nova Scotia", "New Brunswick")

* Some countries have multiple instruments (e.g. both a carbon tax and ETS but also some countries like America only have one as well
* Minimize to one observation per country-year by taking the maximum price.
collapse (max) carbon_price, by(country year)

* Verification step, data 2 factor authentication
codebook country year carbon_price
summarize carbon_price, detail

* Save cleaned carbon price dataset
save "carbon_clean.dta", replace


********************************************************************************
* PART 3: MERGE THE TWO DATASETS
********************************************************************************

* Load the CO2 data as the base
use "co2_clean.dta", clear

* Merge carbon price data (many countries will have no carbon price)
merge 1:1 country year using "carbon_clean.dta"

* _merge == 3: matched in both (has CO2 data AND carbon price)
* _merge == 1: only in CO2 data (no carbon price instrument — set to 0)
* _merge == 2: only in carbon data (no CO2 obs — drop)

replace carbon_price = 0 if _merge == 1   // no carbon price = $0
drop if _merge == 2
drop _merge

label variable carbon_price "Carbon price (USD per tonne CO2)"

* Final check on merged data
summarize
misstable summarize

* Save final panel dataset
save "panel_final.dta", replace


********************************************************************************
* PART 4: PANEL SETUP & DESCRIPTIVE STATISTICS
********************************************************************************

use "panel_final.dta", clear

* Drop observations missing control variables
drop if gdp_per_capita == .
drop if energy_per_gdp == .

* Encode country as numeric ID which allows for panel commands
encode country, gen(country_id)

* Declare panel structure: country_id = unit, year = time
xtset country_id year

* Check panel is balanced/unbalanced
xtdescribe

count

* ---- Descriptive statistics table (Table 1 in your paper) ----
summarize co2_per_capita carbon_price gdp_per_capita energy_per_gdp

* For a formatted table, install estout first: ssc install estout
* Then run:
estpost summarize co2_per_capita carbon_price gdp_per_capita energy_per_gdp
esttab using "table1_desc_stats.rtf", ///
    cells("mean(fmt(2)) sd(fmt(2)) min(fmt(2)) max(fmt(2)) count(fmt(0))") ///
    collabels("Mean" "Std. Dev." "Min" "Max" "N") ///
    title("Table 1: Descriptive Statistics") replace

* ---- Graphical analysis ----

* Figure 1: Scatter plot of carbon price vs CO2 per capita
twoway scatter co2_per_capita carbon_price, ///
    mcolor(teal%40) msize(small) ///
    xtitle("Carbon price (USD/tCO2)") ///
    ytitle("CO2 per capita (tonnes)") ///
    title("Figure 1: Carbon price vs. CO2 emissions per capita")
graph export "figure1_scatter.png", replace

* Figure 2: Average CO2 per capita over time (priced vs unpriced countries)
gen has_price = (carbon_price > 0)
preserve
    collapse (mean) co2_per_capita, by(year has_price)
    twoway (line co2_per_capita year if has_price==1, lcolor(teal)) ///
           (line co2_per_capita year if has_price==0, lcolor(gray)), ///
        legend(label(1 "Countries with carbon price") ///
               label(2 "Countries without carbon price")) ///
        xtitle("Year") ytitle("Avg CO2 per capita (tonnes)") ///
        title("Figure 2: CO2 trends by carbon pricing status")
    graph export "figure2_trends.png", replace
restore


********************************************************************************
* PART 5: REGRESSION ANALYSIS
********************************************************************************

use "panel_final.dta", clear
drop if gdp_per_capita == . | energy_per_gdp == .
encode country, gen(country_id)
xtset country_id year

* ---- Create log-transformed variables ----
* Log-log model: coefficients = elasticities (% change interpretation)
* Add 1 to carbon_price before logging because many values are 0

gen log_co2    = log(co2_per_capita)
gen log_carbon = log(carbon_price + 1)
gen log_gdp    = log(gdp_per_capita)
gen log_energy = log(energy_per_gdp)

label variable log_co2    "Log CO2 per capita"
label variable log_carbon "Log(carbon price + 1)"
label variable log_gdp    "Log GDP per capita"
label variable log_energy "Log energy intensity"

*  Model 1: Baseline — carbon price only, no controls 
* fe = country fixed effects, basically looks at within country differences to prevent from fixed effects such as geography, culture, etc, that do not usually change.
* robust = heteroskedasticity-robust standard errors
eststo m1: xtreg log_co2 log_carbon, fe robust

*  Model 2: Add GDP per capita control 
eststo m2: xtreg log_co2 log_carbon log_gdp, fe robust

*  Model 3: Full model — add energy intensity + year fixed effects 
* year adds a dummy for each year which in turn helps control for normal global trends of time, and global shocks to "all" countries
eststo m3: xtreg log_co2 log_carbon log_gdp log_energy i.year, fe robust

*Export Regressions to Word for analysis in research paper
esttab m1 m2 m3 using "table2_regression.rtf", ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    b(3) se(3) r2 ar2 ///
    keep(log_carbon log_gdp log_energy) ///
    coeflabels(log_carbon "Log(carbon price + 1)" ///
               log_gdp    "Log GDP per capita" ///
               log_energy "Log energy intensity") ///
    mtitles("Model 1" "Model 2" "Model 3") ///
    title("Table 2: Effect of Carbon Pricing on CO2 Emissions Per Capita") ///
    note("Notes: All models use country fixed effects. Robust standard errors in parentheses. * p<0.10, ** p<0.05, *** p<0.01") ///
    replace


********************************************************************************
* PART 6: ROBUSTNESS CHECK
********************************************************************************

* Robustness: restrict sample to countries that EVER had a carbon price
* This tests if the result holds even within the treated group

gen has_price = (carbon_price > 0) if !missing(carbon_price)
replace has_price = 0 if missing(has_price)

bysort country: egen ever_priced = max(has_price)

eststo m4: xtreg log_co2 log_carbon log_gdp log_energy i.year ///
    if ever_priced == 1, fe robust

esttab m3 m4 using "table3_robustness.rtf", ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    b(3) se(3) r2 ///
    keep(log_carbon log_gdp log_energy) ///
    mtitles("Full sample" "Carbon-priced countries only") ///
    title("Table 3: Robustness Check") ///
    note("Robust standard errors in parentheses. * p<0.10, ** p<0.05, *** p<0.01") ///
    replace


********************************************************************************
* PART 7: CLOSE LOG
********************************************************************************

log close

********************************************************************************
* END OF DO-FILE
********************************************************************************

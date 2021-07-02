estimate_prevalence_2020 <- function(connection, cohortDatabaseSchema, cohortTable){
  
  sql <- SqlRender::render("SELECT cohort_definition_id, count(*) count_events, count(distinct subject_id) count_persons
                                        FROM @cohort_database_schema.@cohort_table
                                       GROUP BY cohort_definition_id",
                           cohort_database_schema = cohortDatabaseSchema,
                           cohort_table = cohortTable)
  
  cohorts <- DatabaseConnector::querySql(connection, sql, snakeCaseToCamelCase = T)
  
  sql <- SqlRender::render("SELECT count(*) count_events, count(distinct subject_id) count_persons
                          FROM @cohort_database_schema.@cohort_table
                          WHERE cohort_definition_id IN (1,7)",
                           cohort_database_schema = cohortDatabaseSchema,
                           cohort_table = cohortTable)
  
  symptomatic_or_diagnosed <- DatabaseConnector::querySql(connection, sql, snakeCaseToCamelCase = T)
  
  prevalence <- symptomatic_or_diagnosed$countPersons[1] / cohorts$countPersons[cohorts$cohortDefinitionId==12][1] 
  
  return(coalesce(prevalence, 0.1))
  
}

run_phevaluator_covid <- function(connection, prevalence, cdmDatabaseSchema, cohortDatabaseSchema, cohortTable, outputFolder){
  
  visit_types <- dbGetQuery(connection, 
                            SqlRender::render("SELECT distinct visit_concept_id FROM @cdm_database_schema.visit_occurrence", cdm_database_schema = cdmDatabaseSchema),
                            snakeCaseToCamelCase=T)
  
  excludedCovariateConceptIds <-  c(37311061, 756055)
  
  covSettingsAcute <- createDefaultAcuteCovariateSettings(
    excludedCovariateConceptIds = excludedCovariateConceptIds,
    addDescendantsToExclude = T
  )
  
  covSettingsAcute[[1]]$longTermStartDays <- -28
  covSettingsAcute[[1]]$endDays <- -8
  
  covSettingsAcute[[2]]$shortTermStartDays <- -7
  covSettingsAcute[[2]]$endDays <- 7
  
  covSettingsAcute[[3]]$mediumTermStartDays <- -8
  covSettingsAcute[[3]]$endDays <- 28
  
  cohortArgsAcute <- createCreateEvaluationCohortArgs(
    xSpecCohortId = 1, # C19 diagnosis or positive test
    xSensCohortId = prevalence,  # use proportion rather than a value. No need to exclude xSens from the modelling population given this is confined to 2019, there was no C19 then
    prevalence = prevalence,
    covariateSettings = covSettingsAcute,
    modelPopulationCohortId = 11, # use 2019 as the background population for modelling. There was no C19 then
    evaluationPopulationCohortId = 12, # use all 2020 to assess phenotypes
    visitType = visit_types$visitConceptId, # do not limit visit types given we are using heterogenous DBs
    excludeModelFromEvaluation = FALSE, # no need given time periods are different
    visitLength = 0, # no lower limit to assess outpatients
    startDate = "20190101",
    endDate = "20220101",
    modelType = "acute"
  )
  
  cohortArgsAcute$visitType <- visit_types$visit_concept_id
  
  #create analysis 1
  phenotypes_to_test <- 
    purrr::map(list(diagnosis_or_lab_test = 1, diagnosis = 3, lab_test = 5, symptpmatic = 7, suspected = 9),
               ~createTestPhenotypeAlgorithmArgs(phenotypeCohortId = .x))
  
  pheValuatorAnalysisList <- list(createPheValuatorAnalysis(
    analysisId = 1,
    description = "test_covid_phenotypes",
    createEvaluationCohortArgs = cohortArgsAcute,
    testPhenotypeAlgorithmArgs = phenotypes_to_test
  ))
  
  referenceTable <- covidPhenotypesTest:::runPheValuatorAnalyses(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cdmDatabaseSchema,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTable = cohortTable,
    workDatabaseSchema = cohortDatabaseSchema,
    outputFolder = outputFolder,
    pheValuatorAnalysisList = pheValuatorAnalysisList)
  
}

extract_bitsum <- function(x, bit_names) {
  
  series <- c(2^(1:13))
  
  remainder = x
  combination = c()
  
  while(remainder != 0){
    
    component = match(TRUE, series > remainder) - 1
    
    combination[length(combination)+1] <- component
    
    remainder = remainder - series[component]
  }
  
  return(str_c(bit_names[rev(combination)], collapse=" + "))
  
}
# Copyright 2020 Observational Health Data Sciences and Informatics
#
# This file is part of covidPhenotypesTest
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Execute the cohort diagnostics
#'
#' @details
#' This function executes the cohort diagnostics.
#'
#' @param connectionDetails    An object of type \code{connectionDetails} as created using the
#'                             \code{\link[DatabaseConnector]{createConnectionDetails}} function in the
#'                             DatabaseConnector package.
#' @param cdmDatabaseSchema    Schema name where your patient-level data in OMOP CDM format resides.
#'                             Note that for SQL Server, this should include both the database and
#'                             schema name, for example 'cdm_data.dbo'.
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param oracleTempSchema     Should be used in Oracle to specify a schema where the user has write
#'                             priviliges for storing temporary tables.
#' @param outputFolder         Name of local folder to place results; make sure to use forward slashes
#'                             (/). Do not use a folder on a network drive since this greatly impacts
#'                             performance.
#' @param databaseId           A short string for identifying the database (e.g.
#'                             'Synpuf').
#' @param databaseName         The full name of the database (e.g. 'Medicare Claims
#'                             Synthetic Public Use Files (SynPUFs)').
#' @param databaseDescription  A short description (several sentences) of the database.
#' @param createCohorts        Create the cohortTable table with the exposure and outcome cohorts?
#' @param runSimpleMonthly     Pull monthly counts
#' @param runOverlap           Pull cohort overlap
#' @param minCellCount         The minimum number of subjects contributing to a count before it can be included 
#'                             in packaged results.
#'
#' @export
runPhenoTest <- function(connectionDetails,
                         cdmDatabaseSchema,
                         cohortDatabaseSchema = cdmDatabaseSchema,
                         cohortTable = "cohort",
                         oracleTempSchema = cohortDatabaseSchema,
                         outputFolder,
                         databaseId = "Unknown",
                         databaseName = "Unknown",
                         databaseDescription = "Unknown",
                         createCohorts = TRUE,
                         runSimpleMonthly = TRUE,
                         runOverlap = TRUE,
                         minCellCount = 5) {
  if (!file.exists(outputFolder))
    dir.create(outputFolder, recursive = TRUE)
  
  ParallelLogger::addDefaultFileLogger(file.path(outputFolder, "log.txt"))
  ParallelLogger::addDefaultErrorReportLogger(file.path(outputFolder, "errorReportR.txt"))
  on.exit(ParallelLogger::unregisterLogger("DEFAULT_FILE_LOGGER", silent = TRUE))
  on.exit(ParallelLogger::unregisterLogger("DEFAULT_ERRORREPORT_LOGGER", silent = TRUE), add = TRUE)
  
  if (createCohorts) {
    ParallelLogger::logInfo("Creating cohorts")
    connection <- DatabaseConnector::connect(connectionDetails)
    .createCohorts(connection = connection,
                   cdmDatabaseSchema = cdmDatabaseSchema,
                   cohortDatabaseSchema = cohortDatabaseSchema,
                   cohortTable = cohortTable,
                   oracleTempSchema = oracleTempSchema,
                   outputFolder = outputFolder)
    DatabaseConnector::disconnect(connection)
  }
  
  if(runSimpleMonthly){
    
    connection <- DatabaseConnector::connect(connectionDetails)
    sql <- SqlRender::loadRenderTranslateSql(sqlFilename = "MonthlyCounts.sql",
                                             packageName = "covidPhenotypesTest",
                                             dbms = attr(connection, "dbms"),
                                             oracleTempSchema = oracleTempSchema,
                                             cohort_database_schema = cohortDatabaseSchema,
                                             cohort_table = cohortTable)
    
    counts <- DatabaseConnector::querySql(connection, sql)
    names(counts) <- SqlRender::snakeCaseToCamelCase(names(counts))
    counts$countPersons[counts$countPersons < minCellCount] <- -minCellCount
    write.csv(counts, file.path(outputFolder, "MonthlyCohortCounts.csv"))
    DatabaseConnector::disconnect(connection)
    
  }
  
  if(runOverlap){
    
    connection <- DatabaseConnector::connect(connectionDetails)
    sql <- SqlRender::loadRenderTranslateSql(sqlFilename = "OverlapCounts.sql",
                                             packageName = "covidPhenotypesTest",
                                             dbms = attr(connection, "dbms"),
                                             oracleTempSchema = oracleTempSchema,
                                             cohort_database_schema = cohortDatabaseSchema,
                                             cohort_table = cohortTable)
    
    counts <- DatabaseConnector::querySql(connection, sql)
    names(counts) <- SqlRender::snakeCaseToCamelCase(names(counts))
    counts$countPersons[counts$countPersons < minCellCount] <- -minCellCount
    write.csv(counts, file.path(outputFolder, "CohortOverlap.csv"))
    DatabaseConnector::disconnect(connection)
    
  }

}
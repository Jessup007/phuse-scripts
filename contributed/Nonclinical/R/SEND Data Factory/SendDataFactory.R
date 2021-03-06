# This application can be run for free on a public server at the following address:
# (TBD)
#
# Purpose: Creates SEND datasets with made up data
# Currently can: Allow selections, creates a short ts.xpt file to download
# To use:
#    Get files from github folder Run app in Rstudio
#    Expand and make selections in all left side selectors 
#    Select "Product datasets", they will be downloaded through your browser
#
# Done:
# [Eli] Read in CT versions (selectable by date) for use in Species and strain choices
# [Eli] Read in CT versions (selectable by date) for use in observational domains especially
# [Bob] Update CT read to use web location, use this to show Species choices
# [Bob] SEND IG (for variables, domains and types) read from PDF file into a dataframe
# [Bob] Uses the read SEND IG structure to create the ts.xpt file
#
# Next steps:
# [Bob] Correct labels for each domain, ts.xpt file needs labels set correctly, ensure ts.xpt passes validator 
# [Bob] Structure xls file no longer needed, as now read from SEND IG directly
# [Eli] Allow selection of controlled terminology version dates from GUI
# [Eli] Allow selection of controlled terminology for other dashboard items that should come from controlled terminology. strain is one.
#
# [Kevin] Update so that no errors occur in main window on initial run
# [Kevin] Update so that you see in main windows all the dataset files with row counts and allow drill down to each
# [Kevin] Update measurement choices to cover all possible 3.1 domains
# [Kevin] Configuration files for ranges of numeric fields
# Output of all domains selected
#   [Eli] Trial domains
#   [Eli] Animal demographics and disposition 
#   [Bob] In-life domains 
#   [Bob] Post mortem domains 
# Implementation for SEND 3.1 first, then DART, SEND 3.0
#     
#
#
# install pacakges if needed
.libPaths()
list.of.packages <- c("shiny",
"ggplot2",
"plotly",
"reshape2",
"htmltools",
"RColorBrewer",
"grid",
"GGally",
"reference (",
"represents the",
"Demographics (DM)",
"letters",
"such as",
"the value",
"An example",
"Treated site",
"MASS",
"shinydashboard",
"shinycssloaders",
"httr",
"tools",
"Hmisc",
"XLConnect",
"SASxport",
"utils",
"DT",
"pdftools")



new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos = "http://cran.us.r-project.org")
# Load Libraries
library(shiny)
library(ggplot2)
library(plotly)
library(reshape2)
library(htmltools)
library(RColorBrewer)
library(grid)
library(GGally)
library(MASS)
library(shinydashboard)
library(shinycssloaders)
library(httr)
library(tools)
library(Hmisc)
library(XLConnect)
library(SASxport)
library(utils)
library(DT)
library(pdftools)

if(packageVersion("SASxport") < "1.5.7") {
  stop("You need version 1.5.7 or later of SASxport")
}
# This section is to replace functions in 1.5.7 or SASxport to allow column lengths of less than 8 bytes
# This gives the directory of the file where the statement was placed , to get current .R script directory
sourceDir <- getSrcDirectory(function(dummy) {dummy})
source(paste(sourceDir, "/write.xport2.R", sep=""))
tmpfun <- get("read.xport", envir = asNamespace("SASxport"))
environment(write.xport2) <- environment(tmpfun)
attributes(write.xport2) <- attributes(tmpfun)
assignInNamespace("write.xport", write.xport2, ns="SASxport")
##########

# Functions
convertMenuItem <- function(mi,tabName) {
  mi$children[[1]]$attribs['data-toggle']="tab"
  mi$children[[1]]$attribs['data-value'] = tabName
  mi
}

# read all domain structures
readDomainStructures <-function() {
  withProgress({
    setProgress(value=1,message='Reading domain structures from the SEND IG')
    readSENDIG()
  })
}

isDomainStart <- function(aLine) {
  # Fine the description start
  theDomain <- ""
  pattern <- ".xpt, "
  aLocation <- gregexpr(pattern =pattern,aLine)[[1]][1]
  # if found, and within 8 of begining of line is a table of
  # defining a domain
  if (aLocation>0 & aLocation<9) {
    # found a table start
    # set the domain name
    theDomain <- toupper(substring(aLine,1,aLocation-1))
    print(theDomain)
  }
  theDomain
}

addDomainRow <- function(inLine,inDomain) {
  bResult <- FALSE
  # see if you can split the line into "Column","Type","Label","Codelist","Expectancy"
  Headerpattern1 <- "^Variable {1,}Controlled Terms"
  Headerpattern2 <- "^Variable Label"
  Headerpattern3 <- "^Variable Name"
  Headerpattern4 <- "^Name "
  Headerpattern5 <- "^Controlled Terms"
  aLocation1 <- gregexpr(pattern =Headerpattern1,trimws(inLine))[[1]][1]
  aLocation2 <- gregexpr(pattern =Headerpattern2,trimws(inLine))[[1]][1]
  aLocation3 <- gregexpr(pattern =Headerpattern3,trimws(inLine))[[1]][1]
  aLocation4 <- gregexpr(pattern =Headerpattern4,trimws(inLine))[[1]][1]
  aLocation5 <- gregexpr(pattern =Headerpattern5,trimws(inLine))[[1]][1]
  if (aLocation1>0 | aLocation2>0 | aLocation3>0| aLocation4>0| aLocation5>0) {
  # Header line found, return true since still within the table
    bResult <- TRUE
    print (paste("Debug Header found:",inLine))
  # tables end with a number for the next section
  } else if (!is.numeric(substring(inLine,1,1)) ) {
    aSplit <<- strsplit(inLine,'\\s{2,}')
    if (inDomain=="CV") print (paste("debug A split created",aSplit," for line: ",inLine))
    dataFound <- FALSE
    newRow <- FALSE

    # if the first phrase has field description and merged together
    firstPhrase <-  aSplit[[1]][[1]]
    aLoc <- gregexpr(pattern =" ",trimws(firstPhrase))[[1]][1]
    if (substring(firstPhrase,1,1)==" " & aLoc>1) {
      # split it further
      aSplit[[1]] <<- c(substring(firstPhrase,2,aLoc),
                substring(firstPhrase,aLoc+2),aSplit[[1]][-1] )
    }

    # if expectancy is merged to the end of the split, separate it out
    aLength <- length(aSplit[[1]])
    lastString <- aSplit[[1]][[aLength]]
    lastWord <- tail(strsplit(lastString,split=" ")[[1]],1)
    if ( nchar(lastString)>(nchar(lastWord)+1) & 
         (lastWord == "Req" | lastWord == "Exp" | lastWord == "Perm" )) {
      aSplit[[1]][[aLength+1]] <<- lastWord
      # end remove last word from the previous
      aSplit[[1]][[aLength]] <<- gsub("\\s*\\w*$", "",aSplit[[1]][[aLength]])
    }
    
    # special case of type and codelist making it combine down to 5
    #if 1st ends with Char ISO 8601 and length is 5, make it a 6 by spliting out type and codelist
    if (length(aSplit[[1]])==5) {
      aPart <- aSplit[[1]][[2]]
      aLoc <- gregexpr(pattern =" Char ISO 8601",aPart)[[1]][1]
      if (aLoc>1) {
        theList <- c(aSplit[[1]][[1]],substring(aPart,1,aLoc-1),
                     "Char",
                     "ISO 8601",aSplit[[1]][[3]],
                     aSplit[[1]][[4]],aSplit[[1]][[5]])
        aSplit[[1]] <<- theList
      }
    }
      
    # special case of fields merged to first making it combine down to 4
    #if 1st starts with blank and ends with Char ISO 8601
    if (length(aSplit[[1]])==4) {
      aPart <- aSplit[[1]][[1]]
      aLocF <- gregexpr(pattern ="^ ",aPart)[[1]][1]
      aLoc <- gregexpr(pattern =" Char ISO 8601",aPart)[[1]][1]
      if (aLoc>1 & aLocF==1) {
        aLocS <- gregexpr(pattern =" ",substring(aPart,2))[[1]][1]
        theList <- c(substring(aPart,2,aLocS-1),substring(aPart,aLocS+1,aLoc-1),
                     "Char",
                     "ISO 8601",aSplit[[1]][[2]],
                     aSplit[[1]][[3]],aSplit[[1]][[4]])
        aSplit[[1]] <<- theList
      }
    }

    # special case of fields merged to first making it combine down to 4
    #if 1st starts with blank and ends with Char ISO 8601
    if (length(aSplit[[1]])==4) {
      aPart <- aSplit[[1]][[1]]
      aLocF <- gregexpr(pattern ="^ ",aPart)[[1]][1]
      aLoc <- gregexpr(pattern =" Char ISO 8601",aPart)[[1]][1]
      if (aLoc>1 & aLocF==1) {
        aLocS <- gregexpr(pattern =" ",substring(aPart,2))[[1]][1]
        theList <- c(substring(aPart,2,aLocS),substring(aPart,aLocS+2,aLoc-1),
                     "Char",
                     "ISO 8601",aSplit[[1]][[2]],
                     aSplit[[1]][[3]],aSplit[[1]][[4]])
        aSplit[[1]] <<- theList
      }
    }

    # special case of fields merged to first making it combine down to 4
    #if 1st starts with blank and ends with Char
    if (length(aSplit[[1]])==4) {
      aPart <- aSplit[[1]][[1]]
      aLocF <- gregexpr(pattern ="^ ",aPart)[[1]][1]
      aLoc <- gregexpr(pattern =" Char$",aPart)[[1]][1]
      if (aLoc>1 & aLocF==1) {
        aLocS <- gregexpr(pattern =" ",substring(aPart,2))[[1]][1]
        theList <- c(substring(aPart,2,aLocS),substring(aPart,aLocS+2,aLoc-1),
                     "Char",
                     aSplit[[1]][[2]],
                     aSplit[[1]][[3]],aSplit[[1]][[4]])
        aSplit[[1]] <<- theList
      }
    }

    # special case of fields merged to first making it combine down to 4
    # where column name is merged with description
    if (length(aSplit[[1]])==4) {
      aPart <- trimws(aSplit[[1]][[1]])
      aLoc <- gregexpr(pattern =" ",aPart)[[1]][1]
      if (aLoc>1) {
        theList <- c(substring(aPart,1,aLoc-1),substring(aPart,aLoc+1),
                     aSplit[[1]][[2]],
                     aSplit[[1]][[3]],aSplit[[1]][[4]])
        aSplit[[1]] <<- theList
      }
    }

    if (length(aSplit[[1]])==5) {
      aPart <- aSplit[[1]][[2]]
      # special case if type at end of 2nd field
      aLoc <- gregexpr(pattern =" Char$",aPart)[[1]][1]
      if (aLoc>1) {
        theList <- c(aSplit[[1]][[1]],substring(aPart,1,aLoc-1),
                     "Char",
                     aSplit[[1]][[3]],
                     aSplit[[1]][[4]],aSplit[[1]][[5]])
        aSplit[[1]] <<- theList
      }
    }

    if (length(aSplit[[1]])==5) {
      aPart <- aSplit[[1]][[2]]
      # special case if type at end of 2nd field
      aLoc <- gregexpr(pattern =" Num$",aPart)[[1]][1]
      if (aLoc>1) {
        theList <- c(aSplit[[1]][[1]],substring(aPart,1,aLoc-1),
                     "Num",
                     aSplit[[1]][[3]],
                     aSplit[[1]][[4]],aSplit[[1]][[5]])
        aSplit[[1]] <<- theList
      }
    }

        # some have no code list , making a new row
    if (length(aSplit[[1]])==5) {
      dataFound <- TRUE
      newRow <- TRUE
      aColumn <- trimws(aSplit[[1]][[1]])
      aLabel <- aSplit[[1]][[2]]
      aType <- aSplit[[1]][[3]]
      # sometimes the codelist comes merged with the type
      aTypeLoc <- gregexpr(pattern =" ",aType)[[1]][1]
      if (aTypeLoc>1) {
        aCodeList <- substring(aType,aTypeLoc+1)
        aType <- substring(aType,1,aTypeLoc-1)       
      } else {
        aCodeList <- ""
      }
      anExpectancy <- aSplit[[1]][[5]]
    }
    # if codelist, making a new row
    if (length(aSplit[[1]])==6) {
      dataFound <- TRUE
      newRow <- TRUE
      aColumn <- trimws(aSplit[[1]][[1]])
      aLabel <- aSplit[[1]][[2]]
      aType <- aSplit[[1]][[3]]
      # check if space within type
      aLocType <- gregexpr(pattern =" ",aType)[[1]][1]
      # if Topic or Identifier or Timing, Record or Synonym or Rule, these are Role field
      aWord <- aSplit[[1]][[4]]
      if (aWord != "Topic" & aWord != "Identifier" & aWord != "Result" & aWord != "Timing" &aWord != "Record" &aWord != "Synonym" & aWord != "Rule"& aWord != "Variable"){
        aCodeList <- aSplit[[1]][[4]]
      # If there is a space in the type, then second part is the codelist
      } else if (aLocType>1) {
        aCodeList <- substring(aType,aLocType+1)
        aType <- substring(aType,1,aLocType-1)
      } else {
      aCodeList <- ""
      }
      anExpectancy <- aSplit[[1]][[6]]
    } # end of length check 6
    # if codelist, making a new row
    if (length(aSplit[[1]])==7) {
      dataFound <- TRUE
      newRow <- TRUE
      aColumn <- trimws(aSplit[[1]][[1]])
      aLabel <- aSplit[[1]][[2]]
      aType <- aSplit[[1]][[3]]
      aCodeList <- aSplit[[1]][[4]]
      anExpectancy <- aSplit[[1]][[7]]
    } # end of length check 7
    # if 2 or 3 or 4 in length and first is empty, is a continuation of the label from previous row
    if ((length(aSplit[[1]])==2 | length(aSplit[[1]])==3
                           | length(aSplit[[1]])==4) & (aSplit[[1]][[1]]=="")) {
      # was part of table, discarding because is only about cdisc notes
      dataFound <- TRUE
      # check if should still be adding to row or already finished with description
      if (exists("addMoreToRow") & addMoreToRow<3) {

        # add at most 2 more to row, no variables have more than 3 rows for the label
        addMoreToRow <<- addMoreToRow + 1
        
        # special case, not true that we want to append if starts with certain lines
        aLabel <- aSplit[[1]][[2]]
        aLabel <- trimws(aLabel)
        checkList <- c(
        "each subject",
        "USUBJID",
        "POOLID",
        "COVAL1",
        "group number",
        "multiple records",
        "sequential Element",
        "Treatment, ",
        "when identifying",
        "Qualifier",
        "for the",
        "genetic",
        "must be",
        "whichever",
        "This is ",
        "during the",
        "used ",
        "Codelist,",
        "only",
        "or ,",
        "Pparg",
         "unrelated,",
         "individual,",
         "have,",
         "or AGE",
        "have special",
        "The value",
        "unique ",
        "records that",
        "disposition,",
        "be either",
        "domain records",
        "--DY",
        "The sponsor",
        "calculations",
        "BEAGLE",
        "collected or is missing",
        "Terminology codelist",
        "accomodate",
        "unless",
        "collected",
        "define what",
        "in the data",
        "codelist",
        "excluded",
        "sets or trial",
        "origin",
        "designations",
        "number",
        "Wt",
        "in LBSTRESN",
        "ABNORMAL",
        "Sponsors should",
        "in the LBSPEC",
        "description LBSPEC",
        "terms, utilizing",
        "DOSE",
        "period of",
        "time point",
        "example could",
        "identification should",
        "description MASPEC",
        "VSTESTCD cannot",
        "algorithm for",
        "after dosing",
        "those",
        "specified in",
        "to Treatment",
        "the sponsor",
        "to the sponsor",
        "the reference",
        "variables",
        "should also",
        "NONE",
        "character format",
        "metadata",
        "indicated by",
        "Examples:",
        "mass identification",
        "1 FIRST",
        "semantic value",
        "be left",
        "submitted in",
        "and NEGATIVE",
        "include the",
        " CVTPTNUM and ",
        "to represent",
        "primates")
        # check if any match
        aMatch <- FALSE
        for (aPhrase in checkList) {
          if (gregexpr(pattern =aPhrase,aLabel)[[1]][1]==1) aMatch <- TRUE
        }
        if (!aMatch){
            newRow <- FALSE
            dataFound <- TRUE
            dfSENDIG[nrow(dfSENDIG),]$Label <<- paste(dfSENDIG[nrow(dfSENDIG),]$Label,aLabel)
            # DEBUG - use this next line to clean up the description labels
            # dfSENDIG[nrow(dfSENDIG),]$Label <<- paste(dfSENDIG[nrow(dfSENDIG),]$Label,aLabel,"END?")
        }
      } # end of check if addMoreToRow
    } # end of 2,3,4 length
    # if 2 and starts with copyright character
    if (length(aSplit[[1]])==2 & (substring(aSplit[[1]][[1]],1,1)=='\u00A9')) {
      # continues within table still
      dataFound <- TRUE
    } # end of page break check
    # if 2 and starts with "Final"
    if (length(aSplit[[1]])==2 & (aSplit[[1]][[1]]=="Final")) {
      # continues within table still
      dataFound <- TRUE
    } # end of page break check
    # if 1 and starts with "CDISC Standard"
    if (length(aSplit[[1]])==1 & (substring(aSplit[[1]][[1]],1,14)=="CDISC Standard")) {
      # continues within table still
      dataFound <- TRUE
    } # end of new page check
    
    # add this row
    if (newRow) {
      bResult <- TRUE
      dfSENDIG[nrow(dfSENDIG) + 1,] <<- list(inDomain,aColumn,aType,aLabel,aCodeList,anExpectancy)
      addMoreToRow <<- 0
    }
    if (dataFound) bResult <- TRUE
  } # end of if not numeric
  # debug -
  if (inDomain=="CV") {
    print(paste("For domain: ",inDomain))
    print(aSplit)
    lastSplit <<- aSplit
    print(inLine)
    print(paste(" the length is:",length(aSplit[[1]])))
    }
  bResult
}


convertIGRaw <- function (SENDIGRaw) {
  # using raw text, search and create structure dataframe
  dfSENDIG <<- setNames(data.frame(matrix(ncol = 6, nrow = 1)),
                       c("Domain","Column","Type","Label",
                         "Codelist","Expectancy"))
  # loop through raw looking for the start of a description
  # states are "Searching","FoundDomain"
  aState <- "Searching"
  aCount <- 0
  withProgress({
  for (aPage in SENDIGRaw) {
    for (aLine in aPage) {
      if (aState == "Searching") {
          theDomain <- isDomainStart(aLine)
          if (theDomain != "") { 
            aState <- "FoundDomain"
            aCount <- aCount + 1
            # assume about 30 domains
            setProgress(value=aCount/30,message=paste('Reading domain structure for ',theDomain))
            # give time for user to read
            sleepSeconds(1)
          }
      } else if (aState == "FoundDomain") {
        if (!addDomainRow(aLine,theDomain)) aState <- "Searching"
      }
      
    } # end of line loop
  } # end of Page loop
  })  # end of progress
  # remove first empty row
  dfSENDIG <<- dfSENDIG[-1,]
}

readSENDIG <- function() {
  # FIXME - show error that user must download manually
  # FIXME - due to CDISC login needed
  base <- "https://www.cdisc.org/system/files/members/standard/foundational/send/"
  aZip <- "SENDIG_v_3_1.zip"
  aFile <- "SENDIG_3_1.pdf"
  SENDIGRaw <- readPDFFromURLZip(base,aZip,aFile)
  convertIGRaw(SENDIGRaw)
}

setTSFile <- function(input) {
    # create data frame based on structure
    theColumns <- dfSENDIG[dfSENDIG$Domain=="TS",]$Column
    theLabels <- dfSENDIG[dfSENDIG$Domain=="TS",]$Label
    tsOut <<- setNames(data.frame(matrix(ncol = length(theColumns), nrow = 1)),
                       theColumns
                       )
    # set labels for each field 
    index <- 1
    for (aColumn in theColumns) {
      Hmisc::label(tsOut[[index]]) <<- theLabels[index]
      index <- index + 1
    }
    aRow <- 1
    if (!is.null(input$testArticle)) {
      tsOut[aRow,] <<- list(input$studyName,
                           "TS",
                           aRow,
                           "",
                           "TRT",
                           "Investigational Therapy or Treatment",
                           input$testArticle,
                           "")        
      aRow <- aRow + 1
    }
    if (!is.null(input$species)) {
      tsOut[aRow,] <<- list(input$studyName,
                           "TS",
                           aRow,
                           "",
                           "SPECIES",
                           "Species",
                           input$species,
                           "")        
      aRow <- aRow + 1
    }
    if (!is.null(input$studyType)) {
      tsOut[aRow,] <<- list(input$studyName,
                           "TS",
                           aRow,
                           "",
                           "SSTYP",
                           "Study Type",
                           input$studyType,
                           "")        
      aRow <- aRow + 1
    }
}

# set or create the output data
setOutputData <- function(input) {
   setTSFile(input)  
}

createOutputDirectory <- function (aDir,aStudy) {	
  setwd(aDir)
  if (file.exists(aStudy)){
    setwd(file.path(aDir, aStudy))
  } else {
    dir.create(file.path(aDir, aStudy))
    setwd(file.path(aDir, aStudy))
  }
}

  writeDatasetToTempFile <- function (studyData,domain,domainLabel,tempFile) {
    # get rid of NAs
    studyData[is.na(studyData)] <- ""
    # Set length for character fields
    SASformat(studyData$DOMAIN) <-"$2."	
    # place this dataset into a list with a name
    aList = list(studyData)
    # name it
    names(aList)[1]<-domain
    # and label it
    attr(aList,"label") <- domainLabel
    # write out dataframe
    write.xport2(
      list=aList,
      file = tempFile,
      verbose=FALSE,
      sasVer="7.00",
      osType=R.version.string,	
      cDate=Sys.time(),
      formats=NULL,
      autogen.formats=TRUE
    )
  }


sleepSeconds <- function(x)
{
  p1 <- proc.time()
  Sys.sleep(x)
  proc.time() - p1 # The cpu usage should be negligible
}

addUIDep <- function(x) {
  jqueryUIDep <- htmlDependency("jqueryui", "1.10.4", c(href="shared/jqueryui/1.10.4"),
                                script = "jquery-ui.min.js",
                                stylesheet = "jquery-ui.min.css")
  
  attachDependencies(x, c(htmlDependencies(x), list(jqueryUIDep)))
}

## read worksheet by first downloading a file
readWorksheetFromURL <- function(aLocation,aName,aSheet) {
  subdir <- "downloads"
  createOutputDirectory(sourceDir,subdir)
  aTarget <- paste(sourceDir,subdir,aName,sep="/")
  aURL <- paste(aLocation,aName,sep="/")
  # get file if not aleady downloaded
  if (!file.exists(aTarget)) {
    download.file(aURL,aTarget ,mode = "wb")
  }
  readWorksheetFromFile(aTarget,aSheet)
}

## read pdf by first downloading a file
readPDFFromURLZip <- function(aLocation,aZip,aName) {
  subdir <- "downloads"
  anExDir <- paste(sourceDir,subdir,sep="/")
  createOutputDirectory(sourceDir,subdir)
  aTargetZip <- paste(sourceDir,subdir,aZip,sep="/")
  aTarget <- paste(sourceDir,subdir,aName,sep="/")
  aURL <- paste(aLocation,aZip,sep="/")
  # get file if not aleady downloaded - cannot be done without a login, so assume it is there
  # if (!file.exists(aTargetZip)) {
  #  download.file(aURL,aTargetZip,mode = "wb")
  # }
  # now read from within the zip file, the actual file needed
  unzip(aTargetZip, files = aName, list = FALSE, overwrite = TRUE,
        junkpaths = FALSE, exdir = anExDir, unzip = "internal",
        setTimes = FALSE)
  txt <- pdf_text(aTarget) %>% strsplit(split = "\r\n")
  txt
}

## Read in CT file, This should only be called from the getCT function.
importCT <- function(version) {
  
  # Switch function to determine version
  # Reads directly from the NCI location
  base <- "https://evs.nci.nih.gov/ftp1/CDISC/SEND/Archive"
  df <- switch(version,
               '2019-03' = readWorksheetFromURL(base,"SEND%20Terminology%202019-03-29.xls",
                                                 "SEND Terminology 2019-03-29"),
               '2018-12' = readWorksheetFromURL(base,"SEND%20Terminology%202018-12-21.xls",
                                                 "SEND Terminology 2018-12-21")
  )
  
    
  # Attribute used to determine if user changes CT version.
  attr(df, "version") <- version
  
  df
  
}

# Return CT codelist
getCT <- function(codelist, version) {
  
  # If CT hasn't been loaded in already, superassign to parent environment
  if(!exists("CTdf") || !(attr(CTdf, "version") == version)) CTdf <<- importCT(version)
  
  
  # Return the reqested codelist as a character vector, remove the codelist header row.
  CTdf[(toupper(CTdf$Codelist.Name) == toupper(codelist)) &
         !(is.na(CTdf$Codelist.Code)),]$CDISC.Submission.Value
}

# Source Functions
source('https://raw.githubusercontent.com/phuse-org/phuse-scripts/master/contributed/Nonclinical/R/Functions/Functions.R')
# source('~/PhUSE/Repo/trunk/contributed/Nonclinical/R/Functions/Functions.R')

# Get GitHub Password (if possible)
if (file.exists('~/passwordGitHub.R')) {
  source('~/passwordGitHub.R')
  Authenticate <- TRUE
} else {
  Authenticate <- FALSE
}

# Set Reactive Values
values <- reactiveValues()

# Set Heights and Widths
sidebarWidth <- '300px'
plotHeight <- '800px'

server <- function(input, output, session) {

  # Read domain structures
  readDomainStructures()

  # Store Client Data Regarding previous choices
  cdata <- session$clientData
  
  # Set study name
  output$StudyName <- renderUI({
    # FIXME - remember last choice
    textInput('studyName','Study Name to create:')
  })

  # Set test article
  output$TestArticle <- renderUI({
    # FIXME - remember last choice
    textInput('testArticle','Test article:')
  })
  
  # Display Send versions
  output$SENDVersions <- renderUI({
    # FIXME - these should come from a configuration file
    SENDVersion <- c("SEND IG 3.0","SEND IG 3.1", "DART IG 1.1")
    radioButtons('SENDVersions','Select SEND Version:',SENDVersion,selected=SENDVersion[1])
  })

  # Display output type
  output$Outputtype <- renderUI({
    # FIXME - these should come from a configuration file
    outputtype <- c("XPT files","CSV files")
    radioButtons('outputtype','Select output type:',outputtype,selected=outputtype[1])
  })

    # Display species
  output$Species <- renderUI({
    # Get species choices from the code list
    # FIXME - use the CT version selected by the user
    species <- getCT("SPECIES","2019-03")
    radioButtons('species','Select species:',species,selected=species[1])
  })
  
  # Display output type
  output$Strain <- renderUI({
    # FIXME - these should come from a configuration file,conditional on species
    strain <- c("TBD")
    radioButtons('strain','Select strain:',strain,selected=strain[1])
  })

    # Display Study types
  output$StudyType <- renderUI({
    # FIXME - these should come from a configuration file
    studyType <- c("Single-dose","Multi-dose","Carcinogenicity","Safety Pharm - Respiratory","Safety Pharm - Cardiovascular","Early Fetal Development")
    radioButtons('studyType','Select Study Type:',studyType,selected=studyType[1])
  })

  # Display Subgroups
  output$Subgroups <- renderUI({
    # FIXME - these should come from a configuration file
    subgroups <- c("TK animals","Recovery animals")
    checkboxGroupInput('subgroups','Select set options:',subgroups,selected=subgroups[1])
  })
  
  # Display Number of sex choice
  output$Sex <- renderUI({
    # FIXME - these should come from a configuration file
    sex <- c("Male","Female")
    checkboxGroupInput('sex','Select sex:',sex,selected=c(sex))
  })

    # Display Number of animals per group
  output$AnimalsPerGroup <- renderUI({
    # FIXME - these should come from a configuration file
    animalsPerGroup <- c("4","8","16","20","40","100")
    checkboxGroupInput('animalsPerGroup','Select animals Per Group:',animalsPerGroup,selected=animalsPerGroup[1])
  })

    # Display Test Categories
  output$OutputCategories <- renderUI({
  # FIXME - these should come from a configuration file
    testCategories <- c("Exposure","Body weights","Mass observations","Food consumption","Urinanalysis","Hematology","Organ weights","Macropathology","Micropathology","ECG")
    checkboxGroupInput('testCategories','Data domains to create:',testCategories,selected=testCategories)
  })
  
  # Display Treatment Selection
  output$Treatment <- renderUI({
    # FIXME - these should come from a configuration file
    treatmentList <- c("Control group","Group 2: Low dose","Group 3: Mid dose","Group 4: High dose")
    checkboxGroupInput('treatment',label='Select Treatment Groups:',choices=treatmentList,selected=treatmentList)
  })

  # view TsData
  output$tsData <- renderTable({
    tsOut
  })
  
  # view SEND structure
  output$SENDIGStructure <- renderTable({
    dfSENDIG
  })

    # Downloadable  dataset ----
  # FIXME _ make zip of all the data, all domains
  output$downloadData <- downloadHandler(
    filename = function() {
      "ts.xpt"
    },
    content = function(file) {
      # write to this file
      writeDatasetToTempFile(tsOut,"TS","TRIAL SUMMARY",file)
    }
  )  
  
  # Produce datasets
  observeEvent(ignoreNULL=TRUE,eventExpr=input$produceDatasets,
               handlerExpr={
                 withProgress({
                        setOutputData(input)
                        # FIXME - use temporary directory?
                        tryCatch ({
                          createOutputDirectory(sourceDir,input$studyName)
                        }, error = function(e) {validate(need(FALSE,
                            paste("Unable to create directory. Ensure you have entered a study name "
                            ,e
                            )))})
                        # FIXME - must actually create all domain files
                        # FIXME - must actually create these files
                        aValue <- 1
                        for (aData in input$testCategories) {
                          setProgress(value=aValue,message=paste('Producting dataset',aData))
                          sleepSeconds(1)
                          aValue <- aValue + 1
                        }
                 })
               })
  
}

# NEED TO UPDATE SERVERS AND GITHUB

ui <- dashboardPage(
  
  dashboardHeader(title='SEND data factory',titleWidth=sidebarWidth),
  
  dashboardSidebar(width=sidebarWidth,
                   sidebarMenu(id='sidebar',
                    menuItem('Output settings',icon=icon('database'),startExpanded=T,
                              withSpinner(uiOutput('SENDVersions'),type=7,proxy.height='200px'),
                              withSpinner(uiOutput('Outputtype'),type=7,proxy.height='200px')
                     ),
                     menuItem('Study design',icon=icon('calendar'),startExpanded=F,
                              withSpinner(uiOutput('StudyName'),type=7,proxy.height='200px'),
                              withSpinner(uiOutput('TestArticle'),type=7,proxy.height='200px'),
                              withSpinner(uiOutput('StudyType'),type=7,proxy.height='200px'),
                              withSpinner(uiOutput('Treatment'),type=7,proxy.height='200px'),
                              withSpinner(uiOutput('Subgroups'),type=7,proxy.height='200px')
                     ),
                     menuItem('Animal information',icon=icon('paw'),startExpanded=F,
                              withSpinner(uiOutput('Species'),type=7,proxy.height='200px'),
                              withSpinner(uiOutput('Strain'),type=7,proxy.height='200px'),
                              withSpinner(uiOutput('Sex'),type=7,proxy.height='200px'),
                              withSpinner(uiOutput('AnimalsPerGroup'),type=7,proxy.height='200px')
                     ),
                     menuItem('Data selections',icon=icon('flask'),startExpanded=F,
                              withSpinner(uiOutput('OutputCategories'),type=7,proxy.height='200px')
                     ),
                     menuItem('Produce Data',icon=icon('angle-double-right'),startExpanded=T,
                             actionButton('produceDatasets',label='Produce datasets'),
                             downloadButton("downloadData", "Download dataset")
                     ),
                    menuItem('Other Settings',icon=icon('cogs'),startExpanded=F,
                             actionButton('clearSetup',label='Clear All')
                    )
                   )
  ),
  
  dashboardBody(
    
    tags$script(HTML("$('body').addClass('sidebar-mini');")),
    tags$script(HTML("$('body').addClass('treeview');")),
    h3('SEND IG structure'),
    tableOutput("SENDIGStructure")
  )
  
)

# Run Shiny App
shinyApp(ui = ui, server = server)

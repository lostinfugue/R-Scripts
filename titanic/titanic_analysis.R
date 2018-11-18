test <- read.csv("test.csv",header = TRUE)
train <- read.csv("train.csv",header = TRUE)

## summary stats

## number of survivors vs. non-survivors
survival_summary <- aggregate(x = train$PassengerId
          , by = list(survival_status = train$Survived)
          , FUN = length) 

## same, but by class: 1st, 2nd or 3rd
survival_summary_by_pclass <- aggregate(x = train$PassengerId
          , by = list(survival_status = train$Survived, passenger_class = train$Pclass)
          , FUN = length) 
survival_summary_by_pclass

## same, but by gender
survival_summary_by_sex <- aggregate(x = train$PassengerId
                                        , by = list(survival_status = train$Survived, sex = train$Sex)
                                        , FUN = length) 
survival_summary_by_sex

## same, but by pclass, gender
survival_summary_by_pclass_sex <- aggregate(x = train$PassengerId
                                     , by = list(survival_status = train$Survived, sex = train$Sex, passenger_class = train$Pclass)
                                     , FUN = length) 
survival_summary_by_pclass_sex

# same status but in an easy table
frequencies <- table(train$Pclass, train$Sex, train$Survived)
frequencies <- ftable(train$Pclass, train$Sex, train$Survived)
frequencies
prop.table(frequencies)


#install.packages("gmodels")
library(gmodels)

#very nice output using gmodels package
CrossTable(train$Pclass, train$Survived
#            , prop.c = TRUE
           , prop.r = FALSE
           , prop.t = FALSE
           , prop.chisq = FALSE
           )


hist(train$Age, breaks=seq(0,100,l=11),
     freq=TRUE,col="orange",main="Histogram",
     xlab="x",ylab="f(x)",yaxs="i",xaxs="i")

#install.packages("ggplot2")
library(ggplot2)


ggplot(train,aes(x = Age,fill = as.factor(Survived))) + 
  geom_bar(position = "fill") + stat_bin(bins = 10)


## combine data for initial analysis
test.survived <- data.frame(Survived = rep("None",nrow(test)),test[,])
head(test.survived)

combined <- rbind(train, test.survived)
head(combined)


## change datatypes
str(combined)
combined$Pclass <- as.factor(combined$Pclass)
combined$Survived <- as.factor(combined$Survived)
combined$Name <- as.character(combined$Name)

# 2 extra rows, probably duplicates
length(combined$Name)
length(unique(combined$Name))

## duplicated names
dup.names <- combined[which(duplicated(combined$Name)),"Name"]
dup.names

## get data rows associated with duplicated names
combined[which(combined$Name %in% dup.names),]

## analyze titles found in names (e.g. Miss. Mr, Mrs.)
library(stringr)
?str_detect

## look at rows for "miss"es
## can use str_detect method, which allows regex
misses <- combined[which(str_detect(combined$Name, "Miss.")),]
misses[1:7,]

mrses <- combined[which(str_detect(combined$Name, "Mrs.")),]
mrses[1:7,]


## poor survival rate
## master == young male?
mr <- combined[which(combined$Sex == "male"),]
mr[1:7,]

## create factor variable which represents title extracted from names

## function that compares names to titles using grep
## input is name
## output is title
?grep

grep("Miss.","Andersson, Miss. Anders Joha")
## returns 1 for true, 0 for false

extractTitle <- function(name) {
  name <- as.character(name)
  
  if (length(grep("Miss.",name)) > 0) {
    return ("Miss.")
  } else if (length(grep("Mrs.",name)) > 0) {
    return ("Mrs.")
  } else if (length(grep("Master.",name)) > 0) {
    return ("Master.")
  } else if (length(grep("Mr.",name)) > 0) {
    return ("Mr.")
  } else {
    return("Other")
  }
}

## build a vector from scratch of calculated titles
titles <- NULL

for(i in 1:nrow(combined)) {
  titles <- c(titles, extractTitle(combined$Name[i]))
}

titles
##summarize new field
## 20%  Miss, 58% Mr, 15% Mrs
CrossTable(titles)
## view "Other"s
combined[which(titles=="Other"),]

## add column with factor data type
combined$Title <- as.factor(titles)
train$Title <- as.factor(titles[1:nrow(train)])

## relate title and suvival in table and graph
CrossTable(train$Title,train$Survived)

library(ggplot2)

## title, class and survival
ggplot(combined[1:891,], aes(x= Title, fill= Survived)) +
  geom_bar(width = 0.5) +
  facet_wrap(~Pclass) +
  ggtitle("Pclass") +
  xlab("Title") +
  ylab("Number Survived") +
  labs(fill = "Survived")

## Age, Title and survival
ggplot(combined[1:891,], aes(x= Age, fill= Survived)) +
  geom_bar(width = 0.5) +
  facet_wrap(~Title) +
  ggtitle("Title") +
  xlab("Age") +
  ylab("Number Survived") +
  labs(fill = "Survived")
  


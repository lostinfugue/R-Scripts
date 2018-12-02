##************
##
## Load Data
##
##************

test <- read.csv("test.csv",header = TRUE)
train <- read.csv("train.csv",header = TRUE


##************
##
## Understand Datasets
##
##************

###################
## data types, values
str(train)
str(test)

###################
## summary (distribution of values, number of nulls)
summary(train)
summary(test)

## Survived is the variable we want to classify. it's in train but not test.

###################
## combine (union) data for initial analysis.  include "None" for Survived for rows from test dataset.
test.survived <- data.frame(Survived = rep("None",nrow(test)),test[,])
head(test.survived)

combined <- rbind(train, test.survived)
head(combined)


## change datatypes
str(combined)
combined$Pclass <- as.factor(combined$Pclass)
combined$Survived <- as.factor(combined$Survived)
combined$Name <- as.character(combined$Name)


###################
## Get summary stats on Sex, Pclass, and Survived variables

## number of survivors vs. non-survivors
summary(train$Survived) ## numbers from 0 to 1 inclusive
## 549 0 vs. 342 1
## 61% death rate <-- our error rate if our model predicted 1 every time
## 39% survival rate <-- our error rate if our model predicted 0 every time
## can we do better through incorporating data from features?
survival_summary <- aggregate(x = train$PassengerId ## aggregate function is like a group by in SQL
          , by = list(survival_status = train$Survived)
          , FUN = length) 
survival_summary

#### get equivalent aggregation & summary using dplyr package
# install.packages("dplyr")
library(dplyr)
combined[1:891,] %>% 
  group_by(Survived) %>% 
  summarize(count=n()) %>% 
  mutate(pct = count/sum(count))

## same, but by class: 1st, 2nd or 3rd
summary(train$Pclass) ## numbers 1,2,3.  no n/a's
combined[1:891,] %>% 
  group_by(Survived, Pclass) %>% 
  summarize(count=n()) %>% 
  mutate(pct = count/sum(count))

## same, but by Sex
summary(combined[1:891,"Sex"]) ## factor with male / female
## 74% survival rate for women vs 19% for men
combined[1:891,] %>% 
  group_by(Sex, Survived) %>% 
  summarize(count=n()) %>% 
  mutate(pct = count/sum(count))

## same, but by Pclass, Sex
combined[1:891,] %>% 
  group_by(Sex, Pclass, Survived) %>% 
  summarize(count=n()) %>% 
  mutate(pct = count/sum(count))


## CrossTable from gmodels package is a bit easier to use, like a pivot table
# install.packages("gmodels")
library(gmodels)

#very nice output using gmodels package
CrossTable(combined[1:891,"Pclass"], combined[1:891,"Survived"]
           , prop.c = FALSE ## to false if you want to NOT see pcts of column
           , prop.r = FALSE ## set to false if you want to NOT see pcts of row
           , prop.t = FALSE ## set to false if you want to NOT see pcts of total
           , prop.chisq = FALSE
           )

###################
## Age Variable
## values 0.42 to 80.00; 177 NA's --> 
177/891 ## 20% are N/A
summary(combined[1:891, "Age"])

## histogram of age buckets using base R
hist(train$Age, breaks=seq(0,100,l=11),
     freq=TRUE,col="orange",main="Histogram",
     xlab="x",ylab="f(x)",yaxs="i",xaxs="i")


## histogram of age bins & Survival within each using ggplot2
# install.packages("ggplot2")
library(ggplot2)
ggplot(train,aes(x = ifelse(is.na(Age),-10, Age),fill = as.factor(Survived))) + 
  geom_bar(position = "fill") + stat_bin(bins = 10)

## to-do: Bin ages.  add NA category too.  
## plot histograms of survival with raw counts & pcts


#############
## Names
## character, no NA's
summary(combined[1:891,"Name"])

# 2 extra rows, probably duplicates
length(combined$Name)
length(unique(combined$Name))

## duplicated names
dup.names <- combined[which(duplicated(combined$Name)),"Name"]
dup.names

## get data rows associated with duplicated names
## look to be different people with same name.  OK
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
mr <- combined[which(combined$Sex == "male"),]
mr[1:7,]

## master == young male?

## create factor variable which represents title extracted from names
#### use function that compares names to titles using grep
#### input is name
#### output is title
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
## ship had more men than women
CrossTable(titles)

## view "Other"s
combined[which(titles=="Other"),]

## add column with factor data type
combined$Title <- as.factor(titles)
train$Title <- as.factor(titles[1:nrow(train)])

## relate title and suvival in table and graph
CrossTable(train$Title,train$Survived)

## title, class and survival
pclass.title.summary <- combined[1:891,] %>% 
  group_by(Pclass, Title, Survived) %>% 
  summarize(count=n()) %>% 
  mutate(pct = count/sum(count))

a1 <- ggplot(pclass.title.summary, aes(x=Title, y = pct, fill = Survived)) +
  geom_bar(stat="identity", width = 0.7) +
  facet_wrap(~Pclass)

a2 <- ggplot(pclass.title.summary, aes(x=Title, y = count, fill = Survived)) +
  geom_bar(stat="identity", width = 0.7) +
  facet_wrap(~Pclass)

cowplot::plot_grid(a1,a2, ncol=1, labels = "AUTO")


## Age, Title and survival
ggplot(combined[1:891,], aes(x= Age, fill= Survived)) +
  geom_bar(width = 0.5) +
    stat_bin(bins = 10) +
  facet_wrap(~Title) +
  ggtitle("Title") +
  xlab("Age") +
  ylab("Number Survived") +
  labs(fill = "Survived")
  
## Sex, Title and survival
ggplot(combined[1:891,], aes(x= Sex, fill= Survived)) +
  geom_bar(width = 0.5) +
  facet_wrap(~Pclass) +
  ggtitle("Pclass") +
  xlab("Sex") +
  ylab("Number Survived") +
  labs(fill = "Survived")

##look at summary statistics for age (or any other numeric variable)
?summary
summary(combined)

## 263 missing values for age out of 1309 == 20%
263/1309

summary(combined$Age[1:891])
#177 missing values for age in training set out of 891 =  19.9%
177/891


## plot survival by Sex and PClass
ggplot(combined[1:891, ], aes(x = Age, fill = Survived)) +
  geom_histogram(binwidth = 10) + #bin a numeric variable on x axis
  facet_wrap(~Sex + Pclass) +
  xlab("Age") +
  ylab("Count")

boys <- combined[which(combined$Title=="Master."),]
boys

## plot survival for boys by age bin
ggplot(boys[which(boys$Survived!="None"),], aes(x = Age, fill = Survived)) +
  geom_histogram(binwidth = 5) + #bin a numeric variable on x axis
  xlab("Age") +
  ylab("Count")
## better than average survival rate

## plot survival for misses by age bin
misses <- combined[which(combined$Title=="Miss."),]
misses[1:5,]
ggplot(misses[which(misses$Survived!="None"),], aes(x = Age, fill = Survived)) +
  facet_wrap(~Pclass) +
  geom_histogram(binwidth = 10) + #bin a numeric variable on x axis
  xlab("Age") +
  ylab("Count")
## worse survival rate for 3rd class.  also gets worse with age
## could also classify child misses vs. adult vs. older misses, since seems to be 
## related to survival

## there are some misses who travel alone.  Tend to be adult women instead of children
misses.alone <- misses[which(misses$SibSp==0 & misses$Parch==0),]
misses.alone

summary(boys$Age)
summary(misses$Age)
summary(misses.alone$Age)

summary(combined$SibSp)


## can we treat SibSp as a factor?  i.e. are there few enough different values?
## yes 7 unique values from 0 min to 8 max
length(unique(combined$SibSp))
combined$SibSp <- as.factor(combined$SibSp)
combined$SibSp <- as.integer(combined$SibSp)
combined$SibSp

ggplot(combined[1:891,], aes(x = SibSp, fill = Survived)) +
  geom_histogram(binwidth = 1) + #bin a numeric variable on x axis
  facet_wrap(~Pclass+Title, ncol=5) +
  xlab("SibSp") +
  ylab("Count")
## 3rd class master -- better chance of survival with fewer siblings?

ggplot(combined[1:891,], aes(x = Parch, fill = Survived)) +
  geom_histogram(binwidth = 1) + #bin a numeric variable on x axis
  facet_wrap(~Pclass+Title) +
  xlab("Parch") +
  ylab("Count")

combined$SibSp <- c(train$SibSp, test$SibSp)

## feature engineering?  add a family size variable
as.integer(combined$Parch)
as.integer(combined$SibSp)
combined$family.size <- as.factor(as.integer(combined$Parch) + as.integer(combined$SibSp) + 1)

summary(combined$family.size)
## compare survived to family size
CrossTable(combined[1:891, "family.size"], combined[1:891, "Survived"])

library(scales)

## Graph Survival by Family Size
## seems to increase until 4 then be low.
## could be correlated with socio-economic factors, or not?
# install.packages("cowplot")
family.size.summary <- combined[1:891,] %>% 
  group_by(family.size, Survived) %>% 
  summarize(count=n()) %>% 
  mutate(pct = count/sum(count))

b1 <- ggplot(family.size.summary, aes(x=family.size, y = pct, fill = Survived)) +
  geom_bar(stat="identity", width = 0.7)

b2 <- ggplot(family.size.summary, aes(x=family.size, y = count, fill = Survived)) +
  geom_bar(stat="identity", width = 0.7)

cowplot::plot_grid(b1,b2, ncol=1, labels = "AUTO")


#############
## Fare

## normalize fare by number of accompanying passagengers?
fares = combined %>% 
  select(Survived, SibSp, Title, Sex, Age, Pclass, Parch, family.size, Fare) %>% 
  mutate(Fare.adjusted = Fare / as.integer(family.size))
fares
summary(fares)

## summarize by class (min, max, avg)
## note the use of summarize to pull in multiple measures after aggregating
## had to remove 1 na fare data point from 3rd class
fares.summary.by.class = fares[which(!is.na(fares$Fare.adjusted)),] %>% 
  group_by(Pclass) %>% 
  summarize(min.fare = min(Fare.adjusted)
                        , max.fare = max(Fare.adjusted)
                        , avg.fare = mean(Fare.adjusted))


fares.summary.by.class


fares[which(fares$Fare.adjusted >= 500.),]
fares %>%
  arrange(desc(Fare.adjusted))
fares



ggplot(fares[1:891,], aes(x=Fare.adjusted, fill=Survived)) + 
  geom_histogram(binwidth = 10) +
  facet_wrap(~Pclass) +
  labs(x = "Fare, Adjusted", y = "Survived") +
  xlim(0,100)

# Plot age, Fare per person & age vs. survival as a scatter plot
ggplot(fares[1:891,], aes(x=Fare.adjusted, y = Age, color = Survived)) +
  geom_point() +
  facet_wrap(~Title+Pclass, ncol=3) +
  ggtitle("Pclass")

# Plot age, Fare per person & survival as a scatter plot
ggplot(fares[1:891,], aes(x=Fare.adjusted, y = family.size, color = Survived)) +
  geom_point() +
  facet_wrap(~Title+Pclass, ncol=3) +
  ggtitle("Pclass") +
  xlim(0,200)


## looks like fare estimate could even be useful for understanding survival rate within first class
## nevermind, it looks like that difference was due to women tending to have higher fares
## than men, comparing within 1st class
## doesn't look very useful after all

##############
### Cabin
unique(combined$Cabin) ## 187 unique cabin values
## look at first letters, potentiall number of spaces
combined$Cabin <- as.character(combined$Cabin) 

## lots of empty cabins
## some with multiple cabins listed
combined$Cabin[1:40]

## replace empty cabin with "U" for ease of reading
combined[which(combined$Cabin==""),"Cabin"] <- "U"

## aggregate cabins by first letter
combined$Cabin.first.letter <- substr(combined$Cabin, 1, 1)

## relate Cabin to pclass
CrossTable(combined$Cabin.first.letter, combined$Pclass)

library(dplyr)
cabin.summary <- combined %>% 
  group_by(Cabin.first.letter, Pclass) %>% 
  summarize(count=n()) %>% 
  mutate(pct = count/sum(count))

cabin.summary

## plot summary of cabin composition by class
## almost all the cabin data comes from first class.  some 2nd class.  basically no 3rd class.
#install.packages("cowplot")
g1 <- ggplot(cabin.summary, aes(x=Cabin.first.letter, y = pct, fill = Pclass)) +
  geom_bar(stat="identity", width = 0.7)

g2 <- ggplot(cabin.summary, aes(x=Cabin.first.letter, y = count, fill = Pclass)) +
  geom_bar(stat="identity", width = 0.7)

cowplot::plot_grid(g1, g2, ncol=1, labels = "AUTO")


## relate Cabin to Survival

library(dplyr)
cabin.summary <- combined[1:891,] %>% 
  group_by(Cabin.first.letter, Title, Survived) %>% 
  summarize(count=n()) %>% 
  mutate(pct = count/sum(count))

## plot summary of cabin composition by survival status
##
##install.packages("cowplot")
##honestly this doesn't convey much signal for Survival 
##outside of what's already conveyed from Title/Pclass
g1 <- ggplot(cabin.summary, aes(x=Cabin.first.letter, y = pct, fill = Survived)) +
  geom_bar(stat="identity", width = 0.7) +
  facet_wrap(~Title)

g2 <- ggplot(cabin.summary, aes(x=Cabin.first.letter, y = count, fill = Survived)) +
  geom_bar(stat="identity", width = 0.7) +
  facet_wrap(~Title)

cowplot::plot_grid(g1, g2, ncol=1, labels = "AUTO")


## how about having multiple cabins? does that affect survival rate?
## 41 passengers had multiple cabins listed (3%)
## really not enought to be generalizable
length(combined$Cabin[which(str_detect(combined$Cabin," "))])
41/1309

## 34 (82%) in 1st class, rest in 3rd
CrossTable(combined[which(str_detect(combined$Cabin," ")),"Pclass"])

passengers.multiple.cabins <- combined[which(str_detect(combined$Cabin," ")),] %>% 
  select(Cabin, Pclass, Name, Title, Fare, family.size)

head(passengers.multiple.cabins)

## embarked, Q = Queenstown, S=South Hampton, C = 
str(combined$Embarked)
CrossTable(combined$Embarked)

ggplot(combined[1:891,], aes(x=Embarked, fill=Survived)) +
  geom_bar()

embark.summary <- combined[1:891,] %>% 
  group_by(Title, Embarked, Pclass, Survived) %>% 
  summarize(count=n()) %>% 
  mutate(pct = count/sum(count))

embark.summary

## plot summary of Embarked composition by survival status
##
##install.packages("cowplot")
##honestly this doesn't convey much signal for Survival 
##outside of what's already conveyed from Title/Pclass
d1 <- ggplot(embark.summary, aes(x=Title, y = pct, fill = Survived)) +
  geom_bar(stat="identity", width = 0.7) +
  facet_wrap(~Embarked)

d2 <- ggplot(embark.summary, aes(x=Title, y = count, fill = Survived)) +
  geom_bar(stat="identity", width = 0.7) +
  facet_wrap(~Embarked)

cowplot::plot_grid(d1, d2, ncol=1, labels = "AUTO")

str(combined)

##************
##
## SUMMARY
##
##************

## want these features:
## Survived
## Sex, Title, Pclass, family.size

## maybe want these features:
## Age -- a lot of NA

## don't want these features:
## Name, SibSp, Parch, Ticket, Fare, Cabin, Embarked


##************
##
## Exploratory Modeling
##
##************


# install.packages("randomForest")
library(randomForest)
rf.train.1 <- combined[1:891, c("Pclass","Title")]
rf.label <- as.factor(train$Survived)

set.seed(1234) ## allows for reproduceability across trials


############################
## Model 1
## train 1st model using top 2 features
rf.1 <- randomForest(x = rf.train.1
                     , y = rf.label
                     , importance = TRUE ## track relative importance of features
                     , ntree = 1000 ## default is 500 trees, ok
                     )
rf.1



## confusion matrix: rows show actual label; columns show model's classification.
#### 2% deaths (13/549) were classified as survived
#### 51% survivals (168/342) were classified as died
## overall 20.3% error rate

## recall that 61% of people died in the training set.
## our model does better than just guessing Survived = 0 for everybody
## (20.3% error rate vs. 39% error rate in "naive" approach)

varImpPlot(rf.1)
## features farther to right are more predictive


############################
## Model 2
## train 2nd model for comparison
## 11% deaths classified as survival (false positive)
## 30% survivals classified as death (false negative)
## overall 18.7% error rate (marginally better)
rf.train.2 <- combined[1:891, c("Pclass","Title", "family.size")]
set.seed(1234) ## allows for reproduceability across trials
rf.2 <- randomForest(x = rf.train.2
                     , y = rf.label
                     , importance = TRUE ## track relative importance of features
                     , ntree = 1000 ## default is 500 trees, ok
)
rf.2

############################
## Model 3

## 11% deaths classified as survival (false positive)
## 30% survivals classified as death (false negative)
## overall 18.7% error rate (marginally better)
rf.train.3 <- combined[1:891, c("Pclass","Title","SibSp","Parch")]
set.seed(1234) ## allows for reproduceability across trials
rf.3 <- randomForest(x = rf.train.3
                     , y = rf.label
                     , importance = TRUE ## track relative importance of features
                     , ntree = 1000 ## default is 500 trees, ok
)
rf.3


varImpPlot(rf.2)
varImpPlot(rf.3)



##************
##
## Cross Validation
##
##************


###############
## How to estimate error rate on your model using unseen data



## Subset test records for model
test.submit.df <- combined[892:1309, c("Pclass","Title","family.size")]

## Make predictions
# ?predict
rf.2.preds <- predict(rf.2, test.submit.df)
CrossTable(rf.2.preds)

## convert to csv for submission to kaggle
# ?write.csv
submit.df <- data.frame(PassengerId = rep(892:1309), Survived = rf.2.preds)
write.csv(submit.df, file="RF_SUBMIT_20181125_1.csv", row.names=FALSE)

# install.packages("caret")
# install.packages("doSNOW")
library(caret)
library(doSNOW)

# help(package = "caret")

set.seed(54321)
cv.10.folds <- createMultiFolds(rf.label, k = 10, times = 10)
# ?createMultiFolds

# Check stratification (i.e. our ratio of positive vs. negative predicted outcomes is relatively consistent across folds & samples)
CrossTable(rf.label)
549/342 #1.605


CrossTable(rf.label[cv.10.folds[[12]]])
494/308 #1.604



## set up caret's trainControl object
ctrl.1 <- trainControl(method = "repeatedcv", number = 10, repeats = 10
                       , index = cv.10.folds)

## set up DSNOW to take advantage of multiple cores of computer to thread processes
cl <- makeCluster(6, type="SOCK")
registerDoSNOW(cl)

# set seed for reproduc.
# and train

set.seed(54321)
rf.2.cv.1 <- train(x = rf.train.2, y = rf.label, method = "rf", tuneLength = 3, ntree = 1000, trControl = ctrl.1)
# install.packages("e1071")
# library(e1071)

# shut down cluster
stopCluster(cl)


## checkout results
rf.2.cv.1
##81% acuracy
rf.2
1-.1818
##81.82% accuacy on original rf train

##so slightly lower on cross validation, but we know when submitted to kaggle that accuracy was around 79% so even lower
## could be that with 10 folds, we are still using 90% of data to train, leanding to over sampling




## retry with 5 folds (80% of data used to train)
set.seed(54321)
cv.5.folds <- createMultiFolds(rf.label, k = 5, times = 10)


## set up caret's trainControl object
ctrl.2 <- trainControl(method = "repeatedcv", number = 5, repeats = 10
                       , index = cv.5.folds)

cl <- makeCluster(6, type="SOCK")
registerDoSNOW(cl)

set.seed(54321)
rf.2.cv.2 <- train(x = rf.train.2, y = rf.label, method = "rf", tuneLength = 3, ntree = 1000, trControl = ctrl.2)
stopCluster(cl)
rf.2.cv.2



## still not great
## retry with 3 folds (67% of data used to train)
## without knowingn anything about data, 10folds is good to start
## but also, usually mimicking proportions of actual training and test data sets works well.
set.seed(54321)
cv.3.folds <- createMultiFolds(rf.label, k = 3, times = 10)


## set up caret's trainControl object
ctrl.3 <- trainControl(method = "repeatedcv", number = 3, repeats = 10
                       , index = cv.3.folds)

cl <- makeCluster(6, type="SOCK")
registerDoSNOW(cl)

set.seed(54321)
rf.2.cv.3 <- train(x = rf.train.2, y = rf.label, method = "rf", tuneLength = 3, ntree = 1000, trControl = ctrl.3)
stopCluster(cl)

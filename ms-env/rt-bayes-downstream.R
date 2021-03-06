source("src/packages.R")
file_datestamp <- commandArgs(trailingOnly=TRUE)[1]

# Pull back in environmental data (modified from original model script)
env <- readRDS("clean-data/temp-dailymean-states.RDS")
pop <- readRDS("clean-data/population-density-states.RDS")
meta <- shapefile("clean-data/gadm-states.shp")
processed_data <- readRDS("ms-env/processed_data_usa.RDS")
env <- env[meta$NAME_0=="United States",]
pop <- pop[meta$NAME_0=="United States",]
meta <- meta[meta$NAME_0=="United States",]
meta$code <- sapply(strsplit(meta$HASC_1, ".", fixed=TRUE), function(x) x[2])
env <- env[match(names(processed_data$reported_deaths), meta$code),]
pop <- log10(pop[match(names(processed_data$reported_deaths), meta$code)])
env <- env[,34:148]
sd.env <- sd(env, na.rm=TRUE)
sd.pop <- sd(pop, na.rm=TRUE)
# Remove variables with same names (unnecessary, but done for clarity!)
rm(env,pop,meta,processed_data)

# Get raw coefficients and then back-transform, thne neaten and merge data
load(paste0("ms-env/rt-bayes-",file_datestamp,".Rdata"))
r0 <- unlist(rstan::extract(fit, "mu"))
env <- unlist(rstan::extract(fit, "env_time_slp"))
pop <- unlist(rstan::extract(fit, "pop_slp"))
average <- unlist(rstan::extract(fit, "alpha[1]"))
transit <- unlist(rstan::extract(fit, "alpha[2]"))
residential <- unlist(rstan::extract(fit, "alpha[3]"))
data <- data.frame(
    env, pop, average, transit, residential
)
data$r.env <- data$env/sd.env; data$r.pop <- data$pop/sd.pop

# Calculate mobility changes needed to counter-act env/pop change
# NOTE: using optim for this, rather than algebra, because the
#       posterior distributions of the coefficients aren't always going to
#       be positive or negative (i.e., p!=1) and so you can have problems
#       using logits
# NOTE: using positive term for x*mob.coef because the X data are
#       flipped (i.e., reductions in mobility are positive); discussed
#       with Ettie
inv.logit <- function(x) exp(x) / (exp(x)+1)
logit <- function(x) log(x / (1-x))
optim.func <- function(x, target, mob.coef, new.r0) return(abs(target - (2*new.r0*inv.logit(x*mob.coef))))
optim.wrap <- function(target, mob.coef, new.r0){
    output <- optim(0, optim.func, method="Brent", lower=-10, upper=0, target=target, mob.coef=mob.coef, new.r0=new.r0)
    if(output$convergence != 0)
        stop("Something has gone wrong")
    return(output$par)
}
data$e.four <- data$e.two <- data$e.one <- data$p.twenty <- data$p.ten <- data$p.five <- -999
for(i in seq_len(nrow(data))){
    data$e.four[i] <- optim.wrap(1, data$average[i], 1+abs(data$r.env[i]*4))
    data$e.two[i] <- optim.wrap(1, data$average[i], 1+abs(data$r.env[i]*2))
    data$e.one[i] <- optim.wrap(1, data$average[i], 1+abs(data$r.env[i]*1))
    data$p.twenty[i] <- optim.wrap(1, data$residential[i], 1+abs(data$r.env[i]*log10(20)))
    data$p.ten[i] <- optim.wrap(1, data$residential[i], 1+abs(data$r.env[i]*log10(10)))
    data$p.five[i] <- optim.wrap(1, data$residential[i], 1+abs(data$r.env[i]*log10(5)))
}

summary <- -apply(data[,c("p.twenty","p.ten","p.five","e.four","e.two","e.one")], 2, quantile, prob=c(.05,.1,.25,.5,.75,.9,.95)) * 100
cols <- c("red","red","red","black","black","black")
labels <- c("20x denser population","10x denser population","5x denser population","4°C cooler","2°C cooler","1°C cooler")
cols <- cols[order(summary["50%",])]
labels <- labels[order(summary["50%",])]
summary <- summary[,order(summary["50%",])]

# Generate paper summary statistics
print("Begin summary stats for MS")
summary <- apply(data, 2, quantile, prob=c(.025,.05,.1,.25,.5,.75,.9,.95,.975))
print("Posterior summaries:")
summary["50%",]
print("")
print("P(env < 0):")
(sum(data$env < 0) / nrow(data)) * 100 # Bayesian p-value
print("")
print("P(pop > 0):")
(sum(data$pop > 0) / nrow(data)) * 100 # Bayesian p-value
print("")
print("Posterior correlations:")
cor(data)
print("")
print("Change estimates:")
print(paste0("5 degree change: ", mean(data$r.env)*5))
print(paste0("10x density change: ", mean(data$r.pop)*1))
print("")
print("Model coefficients for supplement:")
xtable(summary(fit, pars=c("alpha","alpha_state","alpha_region","mu","env_time_slp","pop_slp"))$summary)

## Figure 3
# just make 1 new col, then take the distribution, save the quantiles... and overwrite this each new temp/pop

temp_seq <- seq(0.1, 10, 0.1)

# make an empty dataframe to populate with new results
temp_results <- data.frame(temperature = rep(NA, length(temp_seq)))
temp_results$mob_5 <- NA
temp_results$mob_12.5 <- NA
temp_results$mob_50 <- NA
temp_results$mob_87.5 <- NA
temp_results$mob_95 <- NA

for(i in 1:length(temp_seq)){
    temp <- temp_seq[i]
    data$e.temp <- -999
    
    for(j in seq_len(nrow(data))){
        data$e.temp[j] <- optim.wrap(1, data$average[j], 1+abs(data$r.env[j]*temp_seq[i]))
    }
    
    temp_results$temperature[i] <- temp
    temp_results$mob_5[i] <- -quantile(data$e.temp, prob=c(.05))*100
    temp_results$mob_12.5[i] <- -quantile(data$e.temp, prob=c(.125))*100
    temp_results$mob_50[i] <- -quantile(data$e.temp, prob=c(.5))*100
    temp_results$mob_87.5[i] <- -quantile(data$e.temp, prob=c(.875))*100
    temp_results$mob_95[i] <- -quantile(data$e.temp, prob=c(.95))*100
}

# now repeat for population density

pop_seq <- seq(1, 10, 0.1)

# make an empty dataframe to populate with new results
pop_results <- data.frame(pop_density = rep(NA, length(pop_seq)))
pop_results$mob_5 <- NA
pop_results$mob_12.5 <- NA
pop_results$mob_50 <- NA
pop_results$mob_87.5 <- NA
pop_results$mob_95 <- NA

for(i in 1:length(pop_seq)){
    pop <- pop_seq[i]
    data$e.pop <- -999
    
    for(j in seq_len(nrow(data))){
        data$e.pop[j] <- optim.wrap(1, data$average[j], 1+abs(data$r.pop[j]*log10(pop_seq[i])))
    }
    
    pop_results$pop_density[i] <- pop
    pop_results$mob_5[i] <- -quantile(data$e.pop, prob=c(.05))*100
    pop_results$mob_12.5[i] <- -quantile(data$e.pop, prob=c(.125))*100
    pop_results$mob_50[i] <- -quantile(data$e.pop, prob=c(.5))*100
    pop_results$mob_87.5[i] <- -quantile(data$e.pop, prob=c(.875))*100
    pop_results$mob_95[i] <- -quantile(data$e.pop, prob=c(.95))*100
}


fig3 <- ggplot(temp_results) +
    geom_line(aes(x = temperature, y = mob_50), col = "#CC6600", lwd = 2) +
    geom_line(aes(x = temperature, y = mob_12.5), alpha = 0.8, col = "#CC6600", linetype = "dashed", lwd = 1.5) +
    geom_line(aes(x = temperature, y = mob_87.5), alpha = 0.8, col = "#CC6600", linetype = "dashed", lwd = 1.5) +
    geom_line(aes(x = temperature, y = mob_95), alpha = 0.8, col = "#CC6600", linetype = "dotted", lwd = 1) +
    geom_line(aes(x = temperature, y = mob_5), alpha = 0.8, col = "#CC6600", linetype = "dotted", lwd = 1) +
    geom_line(data = pop_results, aes(x = pop_density, y = mob_50), col = "#6666FF", lwd = 2) +
    geom_line(data = pop_results, aes(x = pop_density, y = mob_12.5), alpha = 0.8, col = "#6666FF", linetype = "dashed", lwd = 1.5) +
    geom_line(data = pop_results, aes(x = pop_density, y = mob_87.5), alpha = 0.8, col = "#6666FF", linetype = "dashed", lwd = 1.5) +
    geom_line(data = pop_results, aes(x = pop_density, y = mob_95), alpha = 0.8, col = "#6666FF", linetype = "dotted", lwd = 1) +
    geom_line(data = pop_results, aes(x = pop_density, y = mob_5), alpha = 0.8, col = "#6666FF", linetype = "dotted", lwd = 1) +
    labs(x = "Temperature Decrease (°C)", y = "% Reduction in Mobility to Mitigate") +
    scale_x_continuous(sec.axis = sec_axis(~., name = "X Greater Population Density")) +
    theme_bw() +
    theme(axis.title.x.bottom = element_text(colour = "#CC6600", size = 18, face = "bold"),
          axis.text.x.bottom = element_text(colour = "#CC6600", size = 16, face = "bold"),
          axis.title.x.top = element_text(colour = "#6666FF", size = 18, face = "bold"),
          axis.text.x.top = element_text(colour = "#6666FF", size = 16, face = "bold"),
          axis.text.y = element_text(size = 16, face = "bold"),
          axis.title.y = element_text(size = 18, face = "bold"),
          panel.grid.major.x = element_blank(),
          panel.grid.minor.x = element_blank())
fig3

ggsave("ms-env/US_bayes_plot.pdf", fig3)

# alternative two-panel figure

fig3a <- ggplot(temp_results, aes(x = temperature, y = mob_50)) +
    geom_ribbon(aes(ymin = mob_5, ymax = mob_95), col = "grey", alpha = 0.5) +
    geom_ribbon(aes(ymin = mob_12.5, ymax = mob_87.5), col = "grey", alpha = 0.5) +
    geom_line(col = "black", lwd = 2) +
    labs(x = "Temperature Decrease (°C)", y = "% Reduction in Mobility to Mitigate") +
    ylim(0, 100) +
    theme_bw() +
    theme(axis.text = element_text(size = 16, face = "bold"),
          axis.title = element_text(size = 18, face = "bold"),
          panel.grid.major.x = element_blank(),
          panel.grid.minor.x = element_blank(),
          aspect.ratio = 1)


fig3b <- ggplot(pop_results, aes(x = pop_density, y = mob_50)) +
    geom_ribbon(aes(ymin = mob_5, ymax = mob_95), col = "grey", alpha = 0.5) +
    geom_ribbon(aes(ymin = mob_12.5, ymax = mob_87.5), col = "grey", alpha = 0.5) +
    geom_line(col = "black", lwd = 2) +
    labs(x = "X Greater Population Density", y = "% Reduction in Mobility to Mitigate") +
    ylim(0, 100) +
    theme_bw() +
    theme(axis.text = element_text(size = 16, face = "bold"),
          axis.title = element_text(size = 18, face = "bold"),
          panel.grid.major.x = element_blank(),
          panel.grid.minor.x = element_blank(),
          aspect.ratio = 1)

ggsave("ms-env/US_bayes_plot_a.pdf", fig3a, width = 5, height = 5)
ggsave("ms-env/US_bayes_plot_b.pdf", fig3b, width = 5, height = 5)

#####################################################
# Supplementary figure showing the distributions of #
# the posterior probabilities of main coefficients  #
#####################################################

supp_data <- data.frame(
    r0, env, pop, average, transit, residential
)

posterior_plot <- mcmc_intervals(supp_data, prob_outer = 0.95) +
    scale_y_discrete(limits = rev(c("r0", "env", "pop", "average", "transit", "residential")),
    labels=c(
        "r0" = expression(paste("Overall transmission (",mu, ")")),
        "env" = expression(paste("Temperature (",c, ")")), 
        "pop" =  expression(paste("Population density (",p, ")")),
        "average" = expression(paste("Average mobility (",alpha[1], ")")), 
        "transit" = expression(paste("Transit mobility (",alpha[2], ")")),
        "residential" = expression(paste("Residential mobility (",alpha[3], ")"))
    )) +
    theme_bw() +
    theme(axis.title.x = element_text(size = 18),
          axis.text.x = element_text(size = 16),
          axis.text.y = element_text(size = 16),
          panel.grid.major.x = element_blank(),
          panel.grid.minor.x = element_blank())

ggsave("ms-env/posterior_plot.pdf", posterior_plot)

#####################################################
# Supplementary plots comparing relative influence  #
# of terms in Bayesian model on Rt                  #
#####################################################

main_theme <- theme_bw() + theme(axis.title = element_text(size = 14),
                                 axis.text = element_text(size = 12),
                                 title = element_text(size = 12))

out <- rstan::extract(fit)

# CHANGE THIS to set an alternative output directory for the plots
outdir <- "ms-env/"

make_plot <-  function(state, legend = FALSE){
    
    state_idx <- which(states == state)
    region_idx <- stan_data$Region[state_idx]
    
    state_name <- read.csv("imptf-models/covid19model-6.0/usa/data/states.csv")
    
    full_name <- state_name$State[which(state_name$Abbreviation == state)]
    
    date_state  <-  dates[[state_idx]]
    
    R0 <- as.matrix(out$mu)[,1]
    tempcoef <- as.matrix(out$env_time_slp)[,1]
    popcoef <- as.matrix(out$pop_slp)[,1]
    
    alpha_region <- out$alpha_region[, region_idx, ]
    alpha_state <- out$alpha_state[, state_idx, ]
    
    X <- stan_data$X[state_idx, 1:length(date_state),]
    X_region <- stan_data$X_partial_regional[state_idx, 1:length(date_state),]
    X_state <- stan_data$X_partial_state[state_idx, 1:length(date_state),]
    
    alpha = data.frame(as.matrix(out$alpha))
    colnames(alpha) = labels(terms(formula))
    
    Y <- stan_data$env_time[1:length(date_state), state_idx]
    Z <- rep(stan_data$pop_dat[state_idx], length(date_state))
    
    temperature <- R0 + tempcoef %*% t(Y)
    popdensity <- R0 + popcoef %*% t(Z)
    
    R0_intercept_temp <- rep(1, length(date_state))
    R0_intercept <- R0 %*% t(R0_intercept_temp)
    
    # essentially calculate Rt based on a single term
    # i.e. when all other terms are zero
    
    av_mob <- R0*(2*inv.logit(-alpha[,1] %*% t(X[,1]))) 
    trans_mob <- R0*(2*inv.logit(-alpha[,2] %*% t(X[,2]))) 
    res_mob <- R0*(2*inv.logit(-alpha[,3] %*% t(X[,3]))) 
    
    # all_rhs <- R0 * 2 * inv.logit(-alpha[,1]%*% t(X[,1]) -alpha[,2]%*% t(X[,2])
    #                               -alpha[,3]%*% t(X[,3])
    #             -alpha_region[,1] %*% t(X_region[,1]) -alpha_region[,2] %*% t(X_region[,2]) 
    #             -alpha_state %*% t(X_state)
    #             -week_data)
    
    all_mob <- R0 * 2 * inv.logit(-alpha[,1]%*% t(X[,1]) -alpha[,2]%*% t(X[,2])
                                  -alpha[,3]%*% t(X[,3])
                                  -alpha_region[,1] %*% t(X_region[,1]) -alpha_region[,2] %*% t(X_region[,2]) 
                                  -alpha_state %*% t(X_state))
    
    intercept <- R0*2*inv.logit(-alpha_region[,1] %*% t(X_region[,1]))
    av_mob_region <- R0*2*inv.logit(-alpha_region[,2] %*% t(X_region[,2]))
    
    av_mob_state <- R0*2*inv.logit(-alpha_state %*% t(X_state))
    
    weekly_effect = out$weekly_effect[,,state_idx]
    week_idxs <- stan_data$week_index[state_idx, 1:length(date_state)]
    
    week_data <- NULL
    for (i in 1:length(week_idxs)){
        week_data <- cbind(week_data, weekly_effect[,week_idxs[i]])
    }
    week_data_trans <- R0*2 * inv.logit(-week_data)
    
    # all <- (R0 + tempcoef + popcoef) * 2 * 
    #     inv.logit(-alpha[,1]%*% t(X[,1]) -alpha[,2]%*% t(X[,2]) 
    #               -alpha_region[,1] %*% t(X_region[,1]) -alpha_region[,2] %*% t(X_region[,2]) 
    #               -alpha_state %*% t(X_state)
    #               -week_data)
    Rt <-  out$Rt[, 1:length(date_state), state_idx]
    
    
    df <- data.frame("dates" = date_state,
                     "rt" = colMeans(Rt),
                     "r0" = colMeans(R0_intercept),
                     "temperature" = colMeans(temperature),
                     "popdensity" = colMeans(popdensity),
                     "allmob" = colMeans(all_mob),
                     "ar" = colMeans(week_data_trans))
    
    
    df_long <- gather(df, key = "trend" , value = "value", -dates)
    
    df_long$trend <- factor(df_long$trend,
                            labels = c("Combined mobility", "Autoregressive term", "Population density",
                                       expression(Basic~R[0]), expression(Overall~R[t]), "Temperature"))
    df_long$trend <- factor(df_long$trend,
                            levels = c(expression(Overall~R[t]), expression(Basic~R[0]), "Temperature", "Population density",
                                       "Combined mobility", "Autoregressive term"))
    
    
    p <- ggplot(df_long) + 
        geom_line(aes(dates, value, group = trend, col = trend, linetype = trend),
                  lwd = 1) + 
        scale_color_manual(name = "",
                           values = c("grey", "black", "blue", "red", "orange", "purple"),
                           labels = c(expression(Overall~R[t]), expression(Basic~R[0]), "Temperature", "Population density",
                                      "Combined mobility", "Autoregressive term")) +
        scale_linetype_manual(name = "",
                              values = c("solid", "dotted", "dashed", "dashed", "dashed", "dashed"),
                              labels = c(expression(Overall~R[t]), expression(Basic~R[0]), "Temperature", "Population density",
                                         "Combined mobility", "Autoregressive term")) +
        labs(x ="", y = expression(Contribution~to~R[t]), title = full_name) +
        main_theme
    if(legend == FALSE){
        p <- p + theme(legend.position = "none",
                       aspect.ratio = 1)
    } else{
        p <- p + theme(legend.position = c(0.78, 0.82),
                       legend.text.align = 0,
                       legend.text = element_text(size = 14),
                       aspect.ratio = 1)
    }
    
    # return(p)
    
    # Save it as an svg file.
    svg_file <- paste(outdir, gsub("/|#", "", state), ".pdf", sep="")
    ggsave(filename = svg_file, plot = p, height = 6, width = 6)
    
}

# first state with legend
make_plot(states[1], legend = TRUE)

# all other states without legends
for (i in 2:length(states)) {
    make_plot(states[i], legend = FALSE)
}
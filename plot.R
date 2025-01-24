##
# Graph results from work trials
# $ Rscript plot.R
records <- na.omit(read.csv("records.csv", header=TRUE, colClasses=c("character", "numeric", "numeric"), stringsAsFactors=FALSE))

colors <- rainbow(length(unique(records$strategy)), s = 0.5)

# Group everything
records$group <- interaction(records$strategy, records$io_pct)

# Convert time to ms
ns_in_ms = 1000000
records$time_ms <- records$time / ns_in_ms

png("graph.png", width = 4000, height=2000, res=300)
boxplot(time_ms ~ group,
        data = records,
        col = colors,
        at = rep(unique(records$io_pct), each = 2) + c(-0.2, 0.2),
        main="Fibers vs Threads\nTime to Complete Work\n(lower is better)",
        xlab="Percentage of Workload in IO",
        ylab="Time to Complete Work (ms)",
        las = 1,
        names = rep(unique(records$io_pct), each = 2))

legend(
  "topright",
  legend = unique(records$strategy),
  fill = colors,
  title = "Strategy"
)

dev.off()

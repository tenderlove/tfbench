##
# Graph results from work trials
# $ Rscript plot.R
fiber_times <- na.omit(read.csv("fiber_times.csv", header=TRUE, colClasses=c("numeric", "numeric"), stringsAsFactors=FALSE))
thread_times <- na.omit(read.csv("thread_times.csv", header=TRUE, colClasses=c("numeric", "numeric"), stringsAsFactors=FALSE))

ns_in_ms = 1000000

ymax = max(c(max(fiber_times$time / ns_in_ms), max(thread_times$time / ns_in_ms)))
png("graph.png", width = 4000, height=2000, res=300)
plot(0, main="Fibers vs Threads\nTime to Complete Work\n(lower is better)", type="n", xlab="Percentage of Workload in IO", ylab="Time (ms)", xlim=c(0, 100), ylim=c(0, ymax))
points(thread_times$io_pct, thread_times$time / ns_in_ms, col="blue")
points(fiber_times$io_pct, fiber_times$time / ns_in_ms, col="red", pch=4)
legend("topright", legend=c("Thread Time", "Fiber Time"),
       col=c("blue", "red"), lty=1:1, cex=0.8,
       text.font=4)
 dev.off()

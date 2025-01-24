file "records.csv" do
  ruby "bench.rb"
end

file "graph.png" => "records.csv" do
  sh "Rscript plot.R records.csv graph.png"
end

task default: "graph.png"

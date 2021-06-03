module IRViewer
import InteractiveUtils
using Cascadia
using Gumbo

include("color.jl")
include("ir2graph.jl")
include("run.jl")
include("macro.jl")
export @llvmir2svg,@llvmir2html

end # module

const HTMLTEMPLATE = open(joinpath(@__DIR__,"template.html")) do f
    read(f,String)
end
const SVGTEMPLATE = open(joinpath(@__DIR__,"template.svg")) do f
    read(f,String)
end

function llvm2graphfile(fun,types,filepath,filetype="html")
    # reflection to get the llvm of function
    io = IOBuffer()
    getLLVMIR(io,fun,types)
    io = IOBuffer(String(take!(io)))
    # reparse the ir to get the graph
    funcdef,graphs,blocks = reparse(io)
    name = "$(string(fun))_$(join(string.(types.parameters),'_'))"*".gv"
    # convert the graph to dot file
    indexdict,fullstr = geneNode(blocks,graphs)
    open(joinpath(filepath,name),write=true) do f
        write(f,fullstr)
    end
    # run dot to get svg/html file
    io = IOBuffer()
    rundot(joinpath(filepath,name);dir="",io=io)
    rm(joinpath(filepath,name))
    #post process the svg/html to add comment and remove default title
    s = String(take!(io))
    html = parsehtml(s).root.children[2][1]
    revdict = Dict([indexdict[i]=>i for i in keys(indexdict)])
    for node in eachmatch(Selector("g [class=node]"),html)
        nodename = node.children[1].children[1].text
        #pushfirst!(node.children,r)
        label = revdict[parse(Int,nodename[5:end])]
        intrs = blocks[label]
        alltext = eachmatch(Selector("text"),node)[2:end]
        if length(intrs) != length(alltext)
            global debug = Base.@locals
            error()
        end
        io = IOBuffer()
        for i in eachindex(alltext)
            d = alltext[i].attributes
            datamsg = ""*join(replace(intrs[i][2],'`'=>"&#39"),"<br>")*""
            replace(datamsg,r"[│┌└]+"=>" ")
            if !isempty(strip(datamsg)) && filetype=="html"
                d["data-msg"] = datamsg
                d["onmousemove"] = "showTooltip(evt);" 
                d["onmouseout"] = "hideTooltip();"
            end
            text = alltext[i].children[1].text
            print_llvm_tokens(io,text)
            s = parsehtml(String(take!(io))).root.children[2].children
            empty!(alltext[i].children)
            append!(alltext[i].children,s)
        end
    end
    # finally, output svg or html
    if filetype=="svg"
        s = replace(SVGTEMPLATE,"TEMPLATE"=>string(html))
    elseif filetype =="html"
        s = replace(HTMLTEMPLATE,"TEMPLATE"=>string(html))
    else
        error()
    end
    htmlname = joinpath(filepath,splitext(name)[1]*".$filetype")
    open(htmlname,write=true) do f
        write(f,s)
    end
    return htmlname
end



function getLLVMIR(io,f,types)
    InteractiveUtils.code_llvm(io, f, types; raw=false, dump_module=false, optimize=true)
end

function getLLVMIRTofile(filename,@nospecialize(fun),types)
    open(filename,write=true) do f
        io = IOBuffer()
        getLLVMIR(io,fun,types)
        write(f,take!(io))
    end
    return
end

function reparse(s)
    funcdefplace = readline(s)[4:end]
    funcdef = readline(s)
    Label = String
    cur_block::Label = ""
    blocks = Dict{Label,Vector{Tuple{String,Vector{String}}}}()
    graphs = Dict{Label,Vector{Label}}()
    entry = nothing
    commentstack = String[funcdefplace]
    while !eof(s)
        rawline = readline(s)
        if rawline == "}" && eof(s)
            break
        end
        line = strip(rawline)
        # end of block
        if isempty(line)
            continue
        end
        # is a nested comment
        if line[1] == ';'
            line = strip(line[2:end])
            m = match(r"^(@.*)",line)
            if !isnothing(m)
                commentstack[end] = m.match
                continue
            end
            m = match(r"[│]+ *(@.*)",line)
            if !isnothing(m)
                commentstack[end] = m.match
                continue
            end
            m = match(r"[│]*([┌]+) *(@.*)",line)
            if !isnothing(m)
                l = length(m.captures[1])
                @assert l == 1 "Multiple introduction of comment"
                push!(commentstack,m.match)
                continue
            end
            m = match(r"[│]*([└]+)",line)
            if !isnothing(m)
                l = length(m.captures[1])
                for _ in 1:l
                    pop!(commentstack)
                end
                continue
            end
            println(line)
            error("unreachable")
        end
        m = match(r"^([^: ]+):",line)
        # start of a new block
        if !isnothing(m)
            cur_block = m.captures[1]
            blocks[cur_block] = []
            if isnothing(entry)
                entry = cur_block
            end
            m = match(r"; preds =(.*)",line)
            if !isnothing(m)
                prelabel = map(x->x[2:end],strip.(split(strip(m.captures[1]),',')))
                for l in prelabel
                    if !haskey(graphs,l)
                        graphs[l] = Label[]
                    end
                    push!(graphs[l],cur_block)
                end
            end
            continue
        end
        push!(blocks[cur_block],(rawline,copy(commentstack)))
    end
    if isnothing(entry)
        error("entry is empty")
    end
    pushfirst!(blocks[entry],(strip(funcdef,[' ','\n','{']),[funcdefplace]))
    return funcdef,graphs,blocks
end

function rundot(filename;dir="",typ="svg",io=stdout)
    srcpath = joinpath(dir,filename)
    run(pipeline(`dot -T$typ $srcpath`;stdout=io))
end

function geneNode(blocks,graphs)
    i = 0
    totallabel = []
    indexdict = Dict{String,Int}()
    edges = []
    for label in keys(blocks)
        s = join(map(x->"    "*strip(x[1])*"\\l",blocks[label]),"")
        s = label*":\\l"*s
        s = replace(s,r"\""=>raw"\\\"")
        indexdict[label] = i
        push!(totallabel,"node$i  [label=\"$s\"];")
        i+=1
    end
    for label in keys(blocks)
        if haskey(graphs,label)
            i1 = indexdict[label]
            for child in graphs[label]
                if haskey(indexdict,child)
                    i2 = indexdict[child]
                    push!(edges,"node$i1 -> node$i2;")
                end
            end
        end
    end
    nodestr = join(totallabel,'\n')
    edgestr = join(edges,'\n')
    return (indexdict,"""
        digraph G{
            mindist=0.75;
            ranksep=0.75;
            node [style=filled,fillcolor="#f8f8f8",margin=\"0.1,0.05\",shape=box,]
            $nodestr
            $edgestr
        }
    """)
end

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


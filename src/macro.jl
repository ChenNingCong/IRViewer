macro llvmir2svg(expr,filepath="")
    if expr.head == :call
        assigns = []
        vars = []
        for i in expr.args[2:end]
            var = gensym()
            push!(vars,var)
            push!(assigns,:($var = $(esc(i))))
        end
        return quote
            $(assigns...)
            llvm2graphfile($(esc(expr.args[1])),Base.typesof($(vars...)),$(esc(filepath)),"svg")
        end
    end
end

macro llvmir2html(expr,filepath="")
    if expr.head == :call
        assigns = []
        vars = []
        for i in expr.args[2:end]
            var = gensym()
            push!(vars,var)
            push!(assigns,:($var = $(esc(i))))
        end
        return quote
            $(assigns...)
            llvm2graphfile($(esc(expr.args[1])),Base.typesof($(vars...)),$(esc(filepath)),"html")
        end
    end
end
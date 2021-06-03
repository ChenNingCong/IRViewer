const llvm_types =
    r"^(?:void|half|float|double|x86_\w+|ppc_\w+|label|metadata|type|opaque|token|i\d+)$"
const llvm_cond = r"^(?:[ou]?eq|[ou]?ne|[uso][gl][te]|ord|uno)$" # true|false
const llstyle = Dict{Symbol, Tuple{Bool, Union{Symbol, Int},String}}(
    :default     => (false, :normal,"#000000"), # e.g. comma, equal sign, unknown token
    :comment     => (false, :light_black,"#A9A9A9"),
    :label       => (false, :light_red,"#E77471"),
    :instruction => ( true, :light_cyan,"#5E4FED"),
    :type        => (false, :cyan,"#09ACF8"),#,"#00FFFF"),
    :number      => (false, :yellow,"#ff9700"),
    :bracket     => (true, :yellow,"#000000"),
    :variable    => (false, :normal,"#000000"), # e.g. variable, register
    :keyword     => (false, :light_magenta,"#FF80FF"),
    :funcname    => (true, :light_yellow,"#43eb8f"),
)

function printstyled_ll(io::IO, x, s::Symbol, trailing_spaces="")
    bold=llstyle[s][1]
    color=llstyle[s][3]
    if bold
        print(io,"<tspan fill=\"$color\" font-weight=\"bold\">")
    else
        print(io,"<tspan fill=\"$color\">")
    end
    print(io,x)
    print(io,"&nbsp"^length(trailing_spaces))
    print(io,"</tspan>")
end
const num_regex = r"^(?:\$?-?\d+|0x[0-9A-Fa-f]+|-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)$"

function print_llvm_tokens(io, tokens)
    m = match(r"^((?:[^\s:]+:)?)(\s*)(.*)", tokens)
    if m !== nothing
        label, spaces, tokens = m.captures
        printstyled_ll(io, label, :label, spaces)
    end
    m = match(r"^(%[^\s=]+)(\s*)=(\s*)(.*)", tokens)
    if m !== nothing
        result, spaces, spaces2, tokens = m.captures
        printstyled_ll(io, result, :variable, spaces)
        printstyled_ll(io, '=', :default, spaces2)
    end
    m = match(r"^([a-z]\w*)(\s*)(.*)", tokens)
    if m !== nothing
        inst, spaces, tokens = m.captures
        iskeyword = occursin(r"^(?:define|declare|type)$", inst) || occursin("=", tokens)
        printstyled_ll(io, inst, iskeyword ? :keyword : :instruction, spaces)
    end

    print_llvm_operands(io, tokens)
end

function print_llvm_operands(io, tokens)
    while !isempty(tokens)
        tokens = print_llvm_operand(io, tokens)
    end
    return tokens
end

function print_llvm_operand(io, tokens)
    islabel = false
    while !isempty(tokens)
        m = match(r"^,(\s*)(.*)", tokens)
        if m !== nothing
            spaces, tokens = m.captures
            printstyled_ll(io, ',', :default, spaces)
            break
        end
        m = match(r"^(\*+|=)(\s*)(.*)", tokens)
        if m !== nothing
            sym, spaces, tokens = m.captures
            printstyled_ll(io, sym, :default, spaces)
            continue
        end
        m = match(r"^(\"[^\"]*\")(\s*)(.*)", tokens)
        if m !== nothing
            str, spaces, tokens = m.captures
            printstyled_ll(io, str, :variable, spaces)
            continue
        end
        m = match(r"^([({\[<])(\s*)(.*)", tokens)
        if m !== nothing
            bracket, spaces, tokens = m.captures
            printstyled_ll(io, bracket, :bracket, spaces)
            tokens = print_llvm_operands(io, tokens) # enter
            continue
        end
        m = match(r"^([)}\]>])(\s*)(.*)", tokens)
        if m !== nothing
            bracket, spaces, tokens = m.captures
            printstyled_ll(io, bracket, :bracket, spaces)
            break # leave
        end

        m = match(r"^([^\s,*=(){}\[\]<>]+)(\s*)(.*)", tokens)
        m === nothing && break
        token, spaces, tokens = m.captures
        if occursin(llvm_types, token)
            printstyled_ll(io, token, :type)
            islabel = token == "label"
        elseif occursin(llvm_cond, token) # condition code is instruction-level
            printstyled_ll(io, token, :instruction)
        elseif occursin(num_regex, token)
            printstyled_ll(io, token, :number)
        elseif occursin(r"^@.+$", token)
            printstyled_ll(io, token, :funcname)
        elseif occursin(r"^%.+$", token)
            islabel |= occursin(r"^%[^\d].*$", token) & occursin(r"^\]", tokens)
            printstyled_ll(io, token, islabel ? :label : :variable)
            islabel = false
        elseif occursin(r"^[a-z]\w+$", token)
            printstyled_ll(io, token, :keyword)
        else
            printstyled_ll(io, token, :default)
        end
        printstyled_ll(io,"",:default,spaces)
    end
    return tokens
end
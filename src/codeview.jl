highlighter_exists(config::CthulhuConfig) =
    Sys.which(config.highlighter.exec[1]) !== nothing

__init__() = CONFIG.enable_highlighter = highlighter_exists(CONFIG)

function highlight(io, x, lexer, config::CthulhuConfig)
    config.enable_highlighter || return print(io, x)
    if !highlighter_exists(config)
        @warn "Highlighter command $(config.highlighter.exec[1]) does not exist."
        return print(io, x)
    end
    cmd = `$(config.highlighter) $lexer`
    open(pipeline(cmd; stdout=io, stderr=stderr), "w") do io
        print(io, x)
    end
end

function cthulhu_llvm(io::IO, mi, optimize, debuginfo, params, config::CthulhuConfig)
    dump = InteractiveUtils._dump_function_linfo(
        mi, params.world, #=native=# false,
        #=wrapper=# false, #=strip_ir_metadata=# true,
        #=dump_module=# false, #=syntax=# config.asm_syntax,
        optimize, debuginfo ? :source : :none)
    highlight(io, dump, "llvm", config)
end

function cthulhu_native(io::IO, mi, optimize, debuginfo, params, config::CthulhuConfig)
    dump = InteractiveUtils._dump_function_linfo(
        mi, params.world, #=native=# true,
        #=wrapper=# false, #=strip_ir_metadata=# true,
        #=dump_module=# false, #=syntax=# config.asm_syntax,
        optimize, debuginfo ? :source : :none)
    highlight(io, dump, "asm", config)
end

function cthulhu_ast(io::IO, mi, optimize, debuginfo, params, config::CthulhuConfig)
    meth = mi.def
    ast = definition(Expr, meth)
    if ast!==nothing
        if !config.pretty_ast
            dump(io, ast; maxdepth=typemax(Int))
        else
            show(io, ast)
            # Meta.show_sexpr(io, ast)
            # Could even highlight the above as some kind-of LISP
        end
    else
        @info "Could not retrieve AST. AST display requires Revise.jl to be loaded." meth
    end
end

function cthulhu_source(io::IO, mi, optimize, debuginfo, params, config::CthulhuConfig)
    meth = mi.def
    src, line = definition(String, meth)
    highlight(io, src, "julia", config)
end

cthulhu_warntype(args...) = cthulhu_warntype(stdout, args...)
function cthulhu_warntype(io::IO, src, rettype, debuginfo)
    if VERSION < v"1.1.0-DEV.762"
    elseif VERSION < v"1.2.0-DEV.229"
        lineprinter = Base.IRShow.debuginfo[debuginfo]
    else
        debuginfo = Base.IRShow.debuginfo(debuginfo)
        lineprinter = Base.IRShow.__debuginfo[debuginfo]
    end

    lambda_io::IOContext = stdout
    if src.slotnames !== nothing
        lambda_io = IOContext(lambda_io, :SOURCE_SLOTNAMES =>  Base.sourceinfo_slotnames(src))
    end
    print(io, "Body")
    InteractiveUtils.warntype_type_printer(io, rettype, true)
    println(io)
    if VERSION < v"1.1.0-DEV.762"
        Base.IRShow.show_ir(lambda_io, src, InteractiveUtils.warntype_type_printer)
    else
        Base.IRShow.show_ir(lambda_io, src, lineprinter(src), InteractiveUtils.warntype_type_printer)
    end
    return nothing
end


function cthulu_typed(io::IO, debuginfo_key, CI, rettype, mi, iswarn)
    println()
    println("│ ─ $(string(Callsite(-1, MICallInfo(mi, rettype))))")

    if iswarn
        cthulhu_warntype(stdout, CI, rettype, debuginfo_key)
    elseif VERSION >= v"1.1.0-DEV.762"
        show(stdout, CI, debuginfo = debuginfo_key)
    else
        display(CI=>rt)
    end
    println()
end

# These are standard code views that don't need any special handling,
# This namedtuple maps toggle::Symbol to function
const codeviews = (;
    llvm=cthulhu_llvm,
    native=cthulhu_native,
    ast=cthulhu_ast,
    source=cthulhu_source,
)

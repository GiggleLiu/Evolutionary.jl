"""
Covariance Matrix Adaptation Evolution Strategy Implementation: (μ/μ_I,λ)-CMA-ES

The constructor takes following keyword arguments:

- `μ` is the number of parents
- `λ` is the number of offspring
- `τ` is a time constant for a direction vector `s`
- `τ_c` is a time constant for a covariance matrix `C`
- `τ_σ` is a time constant for a global step size `σ`
"""
@kwdef struct CMAES{TT} <: AbstractOptimizer
    μ::Int = 1
    λ::Int = μ+1
    τ::TT    = NaN
    τ_c::TT  = NaN
    τ_σ::TT  = NaN
end
population_size(method::CMAES) = method.μ
default_options(method::CMAES) = (iterations=1500, abstol=1e-10)

mutable struct CMAESState{T, TI, TT} <: AbstractOptimizerState
    N::Int
    τ::TT
    τ_c::TT
    τ_σ::TT
    fitpop::Vector{T}
    C::Matrix{T}
    s::Vector{T}
    s_σ::Vector{T}
    σ::T
    parent::TI
    fittest::TI
    function CMAESState(N::Int, τ::T1, τ_c::T2, τ_σ::T3, fitpop::Vector{T}, C::Matrix{T},
        s::Vector{T}, s_σ::Vector{T}, σ::T, parent::TI, fittest::TI) where {T, TI, T1, T2, T3}
        TP = promote_type(T1,T2,T3)
        new{T,TI,TP}(N, TP(τ), TP(τ_c), TP(τ_σ), fitpop, C,
            s, s_σ, σ, parent, fittest)
    end
end
value(s::CMAESState) = first(s.fitpop)
minimizer(s::CMAESState) = s.fittest

"""Initialization of CMA-ES algorithm state"""
function initial_state(method::CMAES, options, objfun, population)
    @unpack μ,λ,τ,τ_c,τ_σ = method
    @assert μ < λ "Offspring population must be larger then parent population"

    T = typeof(value(objfun))
    individual = first(population)
    N = length(individual)

    # setup time constraints
    τ = isnan(τ) ? sqrt(N) : τ
    τ_c = isnan(τ_c) ? N^2 : τ_c
    τ_σ = isnan(τ_σ) ? sqrt(N) : τ_σ

    # setup initial state
    return CMAESState(N, τ, τ_c, τ_σ,
            fill(convert(T, Inf), μ),
            diagm(0=>ones(T,N)),
            zeros(T, N), zeros(T, N), one(T),
            copy(individual), copy(individual) )
end

function update_state!(objfun, state, population::AbstractVector{IT}, method::CMAES) where {IT}
    @unpack μ,λ,τ,τ_c,τ_σ = method
    N,σ,τ,τ_c,τ_σ = state.N, state.σ, state.τ, state.τ_c, state.τ_σ

    E = zeros(N, λ)
    W = zeros(N, λ)
    offspring = Array{IT}(undef, λ)
    fitoff = fill(Inf, λ)

    SqrtC = (state.C + state.C') / 2.0
    try
        SqrtC = cholesky(SqrtC).U
    catch ex
        @error "Break on Cholesky: $ex: $(state.C)"
        return true
    end

    for i in 1:λ
        # offspring are generated by transforming standard normally distributed random vectors using a transformation matrix
        E[:,i] = randn(N)
        W[:,i] = σ * (SqrtC * E[:,i])
        offspring[i] = state.parent + W[:,i]   # (L1)
        fitoff[i] = value(objfun, offspring[i]) # Evaluate fitness
    end

    # Select new parent population
    idx = sortperm(fitoff)[1:μ]
    for i in 1:μ
        population[i] = offspring[idx[i]]
        state.fitpop[i] = fitoff[idx[i]]
    end

    w = vec(mean(W[:,idx], dims=2))
    ɛ = vec(mean(E[:,idx], dims=2))
    state.parent += w     #  forming recombinant perent for next generation (L2)
    state.s = (1.0 - 1.0/τ)*state.s + (sqrt(μ/τ * (2.0 - 1.0/τ))/σ)*w     # (L3)
    state.C = (1.0 - 1.0/τ_c).*state.C + (state.s./τ_c)*state.s'          # (L4)
    state.s_σ = (1.0 - 1.0/τ_σ)*state.s_σ + sqrt(μ/τ_σ*(2.0 - 1.0/τ_σ))*ɛ # (L5)
    state.σ = σ*exp(((state.s_σ'*state.s_σ)[1] - N)/(2*N*sqrt(N)))

    state.fittest = population[1]

    return false
end

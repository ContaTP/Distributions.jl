doc"""
    Binomial(n,p)

A *Binomial distribution* characterizes the number of successes in a sequence of independent trials. It has two parameters: `n`, the number of trials, and `p`, the probability of success in an individual trial, with the distribution:

$P(X = k) = {n \choose k}p^k(1-p)^{n-k},  \quad \text{ for } k = 0,1,2, \ldots, n.$

```julia
Binomial()      # Binomial distribution with n = 1 and p = 0.5
Binomial(n)     # Binomial distribution for n trials with success rate p = 0.5
Binomial(n, p)  # Binomial distribution for n trials with success rate p

params(d)       # Get the parameters, i.e. (n, p)
ntrials(d)      # Get the number of trials, i.e. n
succprob(d)     # Get the success rate, i.e. p
failprob(d)     # Get the failure rate, i.e. 1 - p
```

External links:

* [Binomial distribution on Wikipedia](http://en.wikipedia.org/wiki/Binomial_distribution)
"""
immutable Binomial <: DiscreteUnivariateDistribution
    n::Int
    p::Float64

    function Binomial(n::Real, p::Real)
        @check_args(Binomial, n >= zero(n))
        @check_args(Binomial, zero(p) <= p <= one(p))
        new(n, p)
    end
    function Binomial(n::Real)
        @check_args(Binomial, n >= zero(n))
        new(n, 0.5)
    end
    Binomial() = new(1, 0.5)
end

@distr_support Binomial 0 d.n


#### Parameters

ntrials(d::Binomial) = d.n
succprob(d::Binomial) = d.p
failprob(d::Binomial) = 1.0 - d.p

params(d::Binomial) = (d.n, d.p)


#### Properties

mean(d::Binomial) = ntrials(d) * succprob(d)
var(d::Binomial) = ntrials(d) * succprob(d) * failprob(d)
mode(d::Binomial) = ((n, p) = params(d); n > 0 ? round(Int,(n + 1) * d.prob) : 0)
modes(d::Binomial) = Int[mode(d)]

median(d::Binomial) = round(Int,mean(d))

function skewness(d::Binomial)
    n, p1 = params(d)
    p0 = 1.0 - p1
    (p0 - p1) / sqrt(n * p0 * p1)
end

function kurtosis(d::Binomial)
    n, p = params(d)
    u = p * (1.0 - p)
    (1.0 - 6.0 * u) / (n * u)
end

function entropy(d::Binomial; approx::Bool=false)
    n, p1 = params(d)
    (p1 == 0.0 || p1 == 1.0 || n == 0) && return 0.0
    p0 = 1.0 - p1
    if approx
        return 0.5 * (log(twoπ * n * p0 * p1) + 1.0)
    else
        lg = log(p1 / p0)
        lp = n * log(p0)
        s = exp(lp) * lp
        for k = 1:n
           lp += log((n - k + 1) / k) + lg
           s += exp(lp) * lp
        end
        return -s
    end
end


#### Evaluation & Sampling

@_delegate_statsfuns Binomial binom n p

rand(d::Binomial) = convert(Int, StatsFuns.Rmath.binomrand(d.n, d.p))

immutable RecursiveBinomProbEvaluator <: RecursiveProbabilityEvaluator
    n::Int
    coef::Float64   # p / (1 - p)
end

RecursiveBinomProbEvaluator(d::Binomial) = RecursiveBinomProbEvaluator(d.n, d.p / (1.0 - d.p))
nextpdf(s::RecursiveBinomProbEvaluator, pv::Float64, x::Integer) = ((s.n - x + 1) / x) * s.coef * pv

function _pdf!(r::AbstractArray, d::Binomial, X::UnitRange)
    vl,vr, vfirst, vlast = _pdf_fill_outside!(r, d, X)
    if succprob(d) <= 0.5
        # fill normal
        rpe = RecursiveBinomProbEvaluator(d::Binomial)

        # fill central part: with non-zero pdf
        if vl <= vr
            fm1 = vfirst - 1
            r[vl - fm1] = pv = pdf(d, vl)
            for v = (vl+1):vr
                r[v - fm1] = pv = nextpdf(rpe, pv, v)
            end
        end
    else
        # fill reversed to avoid 1/0 for d.p==1.
        rpe = RecursiveBinomProbEvaluator(d.n, (1.0 - d.p) / d.p)

        # fill central part: with non-zero pdf
        if vl <= vr
            fm1 = vfirst - 1
            r[vr - fm1] = pv = pdf(d, vr)
            for v = (vr-1):-1:vl
                r[v - fm1] = pv = nextpdf(rpe, pv, d.n-v)
            end
        end
    end
    return r
end

function mgf(d::Binomial, t::Real)
    n, p = params(d)
    (1.0 - p + p * exp(t)) ^ n
end

function cf(d::Binomial, t::Real)
    n, p = params(d)
    (1.0 - p + p * cis(t)) ^ n
end


#### Fit model

immutable BinomialStats <: SufficientStats
    ns::Float64   # the total number of successes
    ne::Float64   # the number of experiments
    n::Int        # the number of trials in each experiment

    BinomialStats(ns::Real, ne::Real, n::Integer) = new(ns, ne, n)
end

function suffstats{T<:Integer}(::Type{Binomial}, n::Integer, x::AbstractArray{T})
    ns = zero(T)
    for i = 1:length(x)
        @inbounds xi = x[i]
        0 <= xi <= n || throw(DomainError())
        ns += xi
    end
    BinomialStats(ns, length(x), n)
end

function suffstats{T<:Integer}(::Type{Binomial}, n::Integer, x::AbstractArray{T}, w::AbstractArray{Float64})
    ns = 0.
    ne = 0.
    for i = 1:length(x)
        @inbounds xi = x[i]
        @inbounds wi = w[i]
        0 <= xi <= n || throw(DomainError())
        ns += xi * wi
        ne += wi
    end
    BinomialStats(ns, ne, n)
end

typealias BinomData Tuple{Int, AbstractArray}

suffstats(::Type{Binomial}, data::BinomData) = suffstats(Binomial, data...)
suffstats(::Type{Binomial}, data::BinomData, w::AbstractArray{Float64}) = suffstats(Binomial, data..., w)

fit_mle(::Type{Binomial}, ss::BinomialStats) = Binomial(ss.n, ss.ns / (ss.ne * ss.n))

fit_mle{T<:Integer}(::Type{Binomial}, n::Integer, x::AbstractArray{T}) = fit_mle(Binomial, suffstats(Binomial, n, x))
fit_mle{T<:Integer}(::Type{Binomial}, n::Integer, x::AbstractArray{T}, w::AbstractArray{Float64}) = fit_mle(Binomial, suffstats(Binomial, n, x, w))
fit_mle(::Type{Binomial}, data::BinomData) = fit_mle(Binomial, suffstats(Binomial, data))
fit_mle(::Type{Binomial}, data::BinomData, w::AbstractArray{Float64}) = fit_mle(Binomial, suffstats(Binomial, data, w))

fit(::Type{Binomial}, data::BinomData) = fit_mle(Binomial, data)
fit(::Type{Binomial}, data::BinomData, w::AbstractArray{Float64}) = fit_mle(Binomial, data, w)

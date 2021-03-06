

# ****************************************************************
#                      1D heat conduction
# ****************************************************************


"""
- `A_B`   : Bond albedo
- `A_TH`  : Albedo at thermal radiation wavelength
- `k`     : Thermal conductivity
- `ρ`     : Density [kg/m³]
- `Cₚ`    : Heat capacity [J/kg/K]
- `ϵ`     : Emissivity
- `P`     : Rotation period [s]
- `l`     : Thermal skin depth
- `Γ`     : Thermal inertia
- `Δt`    : Time step
- `t_bgn` : Start time of the simulation
- `t_end` : End time of the simulation
- `Nt`    : Number of time step
- `Δz`    : Depth step
- `z_max` : Maximum depth for themal simualtion
- `Nz`    : Number of depth step
- `λ`     : Non-dimensional coefficient for heat diffusion equation
"""
struct ParamsThermo{T}
    A_B::T
    A_TH::T
    k::T
    ρ::T
    Cₚ::T
    ϵ::T
    P::T
    l::T
    Γ::T
    Δt::T
    t_bgn::T
    t_end::T
    Nt::Int64
    Δz::T
    z_max::T
    Nz::Int64
    λ::T
end


function ParamsThermo(; A_B, A_TH, k, ρ, Cₚ, ϵ, P, Δt, t_bgn, t_end, Δz, z_max)
    l = getThermalSkinDepth(P, k, ρ, Cₚ)
    Γ = getThermalInertia(k, ρ, Cₚ)
    
    Δt /= P
    t_bgn /= P
    t_end /= P
    Nt = length(t_bgn:Δt:t_end)
    
    Δz /= l
    z_max /= l
    Nz = length(0:Δz:z_max)
    
    λ = 1/4π * (Δt/Δz^2)
    λ > 0.5 && println("λ should be smaller than 0.5 for convergence.")
    
    ParamsThermo(A_B, A_TH, k, ρ, Cₚ, ϵ, P, l, Γ, Δt, t_bgn, t_end, Nt, Δz, z_max, Nz, λ)
end


function Base.show(io::IO, params_thermo::ParamsThermo)
    @unpack A_B, A_TH, k, ρ, Cₚ, ϵ, P, l, Γ, Δt, t_bgn, t_end, Nt, Δz, z_max, Nz, λ = params_thermo
    
    println(io, "Thermophysical parameters")
    println("-------------------------")
    
    println("A_B   : ", A_B)
    println("A_TH  : ", A_TH)
    println("k     : ", k)
    println("ρ     : ", ρ)
    println("Cₚ    : ", Cₚ)
    println("ϵ     : ", ϵ)
    println("P     : ", P)
    println("l     : ", l)
    println("Γ     : ", Γ)
    println("Δt    : ", Δt)
    println("t_bgn : ", t_bgn)
    println("t_end : ", t_end)
    println("Nt    : ", Nt)
    println("Δz    : ", Δz)
    println("z_max : ", z_max)
    println("Nz    : ", Nz)
    println("λ     : ", λ)
end


"""
    getThermalSkinDepth(P, k, ρ, Cₚ) -> l_2π

# Arguments
- `P`  :
- `k`  :
- `ρ`  :
- `Cₚ` :

# Return
`l_2π` : Thermal skin depth
"""
getThermalSkinDepth(P, k, ρ, Cₚ) = √(4π * P * k / (ρ * Cₚ))
getThermalSkinDepth(params) = getThermalSkinDepth(params.P, params.k, params.ρ, params.Cₚ)


"""
    getThermalInertia(k, ρ, Cₚ) -> Γ

# Arguments
- `k`  :
- `ρ`  :
- `Cₚ` :

# Return
`Γ` : Thermal inertia
"""
getThermalInertia(k, ρ, Cₚ) = √(k * ρ * Cₚ)
getThermalInertia(params) = getThermalInertia(params.k, params.ρ, params.Cₚ)


"""
    update_temperature!(Tⱼ, Tⱼ₊₁, F, params_thermo)

Update temerature profie based on 1-D heat diffusion

# Arguments
- `Tⱼ`            : Temperatures
- `Tⱼ₊₁`          : Temperatures at the next time step
- `F`             : Energy flux to the surface 
- `params_thermo` : Thermophysical parameters

i : index of depth
j : index of time step

for i in 2:length(Tⱼ)-1
    Tⱼ₊₁[i] = (1-2λ)*Tⱼ[i] + λ*(Tⱼ[i+1] + Tⱼ[i-1])
end
"""
function update_temperature!(Tⱼ, Tⱼ₊₁, F, params_thermo)
    @unpack λ = params_thermo
    
    @. Tⱼ₊₁[begin+1:end-1] = @views (1-2λ)*Tⱼ[begin+1:end-1] + λ*(Tⱼ[begin+2:end] + Tⱼ[begin:end-2])
    
    update_surface_temperature!(Tⱼ₊₁, F, params_thermo)  # Sourface boundary condition (Radiation)
    Tⱼ₊₁[end] = Tⱼ₊₁[end-1]                              # Internal boundary condition (Insulation)
    
    Tⱼ .= Tⱼ₊₁
end


function update_temperature!(shape, params_thermo)
    @unpack A_B, A_TH = params_thermo
                    
    for smesh in shape.smeshes
        @unpack sun, scat, rad = smesh.flux
        F_total = (1 - A_B)*(sun + scat) + (1 - A_TH)*rad

        update_temperature!(smesh.Tz, shape.Tz⁺, F_total, params_thermo)
    end
end


"""
    updateSurfaceTemperature!(T, F, params_thermo)

Solve Newton's method to get surface temperature 
"""
function update_surface_temperature!(T, F, params_thermo)
    @unpack Δz, Γ, P, ϵ = params_thermo

    for _ in 1:20
        T_pri = T[begin]

        f = F + Γ / √(4π * P) * (T[begin+1] - T[begin]) / Δz - ϵ*σ_SB*T[begin]^4
        df = - Γ / √(4π * P) / Δz - 4*ϵ*σ_SB*T[begin]^3             
        T[begin] -= f / df

        err = abs(1 - T_pri / T[begin])
        err < 1e-10 && return
    end
end


# ****************************************************************
#
# ****************************************************************


"""
Intensity of radiation at a wavelength λ and tempertature T
according to the Planck function
"""
function getintensity(λ, T)
    h = 6.62607015e-34  # Planck constant [J⋅s]
    k = 1.380649e-23    # Boltzmann's constant [J/K]

    I = 2 * h * c^2 / λ^5 / (exp(h * c₀ / (λ * k * T)) - 1)
end


ν2λ(ν) = c₀ / ν
λ2ν(λ) = c₀ / λ


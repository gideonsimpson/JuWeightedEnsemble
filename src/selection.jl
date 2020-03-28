"""
`build_coarse_vectors`: Assemble the conditional expectation and 1- step
variance approximations one a coarser model, given the transition matrix, `K̃`,
and a coarse scale QoI function, `f̃`.

### Arguments
* `n_we_steps` - number of WE steps
* `K̃` - coarse scale transition matrix
* `f̃` - quantity of interest vector on the bin space
"""
function build_coarse_vectors(n_we_steps, K̃, f̃)
   n_bins = length(f̃);
   ṽ²_vals = [zeros(n_bins) for j in 1:n_we_steps];
   h̃_vals = [zeros(n_bins) for j in 1:n_we_steps+1];
   h̃ = deepcopy(f̃);
   K̃h̃ =similar(f̃);
   # vector of 1's
   e = ones(n_bins);
   @. h̃_vals[end] = h̃;

   # Use t+1 in indexing since Julia arrays start at 1
   for t in n_we_steps-1:-1:0

      K̃h̃ .= K̃ * h̃;
      # compute variance row by row
      for p in 1:n_bins
           ṽ²_vals[t+1][p] = K̃[p,:]⋅((h̃ .- e * (K̃h̃[p])).^2)
      end
      # update for next iterate
      @. h̃ = K̃h̃;
      @. h̃_vals[t+1] = h̃;
   end

   return h̃_vals, ṽ²_vals
end


"""
`optimal_allocation_selection!`: Optimally particles according to the bins,
using a value function to approximate mutation variance.

### Arguments
* `E` - particle ensemble
* `B` - bin data structure
* `v²` - v² variance function estimator
* `t` - t-th seletion step
* `resample` - resampling scheme
"""
function optimal_allocation_selection!(E::Ensemble, B::Bins, v², t; resample=Systematic)

   n_particles = length(E);
   n_bins = length(B);
   # zero out offspring counts
   @. E.o = 0;
   @. B.target = 0;

   # identify nonempty bins
   non_empty_bins = findall(n->n>0, B.n);
   R = length(non_empty_bins);
   Ñ = zeros(n_bins);

   for p in non_empty_bins
      particle_ids = findall(isequal(p), E.b);
      Ñ[p] = sqrt(B.ν[p] * sum(E.ω[particle_ids] .* v².(E.ξ[particle_ids],t)));
   end

   if(sum(Ñ)>0)
      # normalize
      Ñ .= n_particles * Ñ/sum(Ñ);
      B.target .= (B.n .>0) .+ resample(n_particles-R, Ñ./n_particles);

      # compute number of offspring of each particle bin by bin
      for p in non_empty_bins
         # get particle indices for bin p
         particle_ids = findall(isequal(p), E.b);
         E.o[particle_ids] = resample(B.target[p], E.ω[particle_ids]/B.ν[p]);
      end

   else
      # every particle copies itself
      B.target .= B.n;
      @. E.o = 1;
   end

   # resample the particles
   n_spawned = 0;
   for i in 1:n_particles
      # identify the bin of the current particle
      bin = E.b[i];
      for k in 1:E.o[i]
         E.ξ̂[k+n_spawned] = deepcopy(E.ξ[i]);
         E.ω̂[k+n_spawned] = B.ν[bin]/B.target[bin];
         E.b̂[k+n_spawned] = bin;
      end
      n_spawned += E.o[i];
   end
   E, B
end

"""
`uniform_selection!`: Uniformly select particles, ensuring each bin with
positive bin weight has at least one offspring.

### Arguments
* `E` - particle ensemble
* `B` - bin data structure
* `resample` - resampling scheme
"""
function uniform_selection!(E::Ensemble, B::Bins; resample=Systematic)
   n_particles = length(E);
   n_bins = length(B);
   # zero out offspring counts
   @. E.o = 0;
   @. B.target = 0;

   # ensure each bin with walkers has at least one offspring
   non_empty_bins = findall(n->n>0, B.n);
   R = length(non_empty_bins);
   B.target[non_empty_bins] .= 1 .+ resample(n_particles-R, [1.0/R for j in 1:R]);

   # compute number of offspring of each particle bin by bin
   for p in non_empty_bins
      # get particle indices for bin p
      particle_ids = findall(isequal(p), E.b);
      E.o[particle_ids] .= resample(B.target[p], E.ω[particle_ids]/B.ν[p]);
   end

   # resample the particles
   n_spawned = 0;
   for i in 1:n_particles
      # identify the bin of the current particle
      bin = E.b[i];
      for k in 1:E.o[i]
         E.ξ̂[k+n_spawned] = deepcopy(E.ξ[i]);
         E.ω̂[k+n_spawned] = B.ν[bin]/B.target[bin];
         E.b̂[k+n_spawned] = bin;
      end
      n_spawned += E.o[i];
   end
   E, B
end

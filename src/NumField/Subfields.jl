export fixed_field, subfields

add_verbosity_scope(:Subfields)

# Compute basis for the subfield of K that is generated by the elements of as.
function _subfield_basis(K::S, as::Vector{T}) where {
    S <: Union{AnticNumberField, Hecke.NfRel},
    T <: Union{nf_elem, Hecke.NfRelElem}
   }
  if isempty(as)
    return elem_type(K)[gen(K)]
  end

  # Notation: k base field, K the ambient field, F the field generated by as

  k = base_field(K)

  d = degree(K)
  Kvs = VectorSpace(k, d)
  # We transition the coefficients of a in reverse order, so that the
  # first vector in the row reduced echelon form yields the highest
  # degree among all elements of Fas.
  (Fvs,phivs) = sub(Kvs, [Kvs([coeff(a,n) for n in d-1:-1:0])
                          for a in as])
  dF = length(Fvs.gens) # dim(Fvs)
  bs = as
  while !isempty(bs)
    nbs = elem_type(K)[]
    for b in bs
      abs = elem_type(K)[a*b for a in as]
      abvs,_ = sub(Kvs, [Kvs([coeff(ab,n) for n in d-1:-1:0])
                         for ab in abs])
      (Fvs,phivs) = sub(Kvs, typeof(Fvs)[Fvs, abvs])
      if dF != length(Fvs.gens) # dim(Fvs)
        dF = length(Fvs.gens) # dim(Fvs)
        append!(nbs, abs)
      end
    end
    bs = nbs
  end

  kx = parent(K.pol)
  return elem_type(K)[let Kv = phivs(v)
            K(kx([Kv[n] for n in d:-1:1]))
          end
          for v in gens(Fvs)]::Vector{elem_type(K)}
end

function _improve_subfield_basis(K, bas)
  # First compute the maximal order of <bas> by intersecting and saturating
  # Then B_Ok = N * B_LLL_OK
  # Then B' defined as lllN * B_LLL_OK will hopefully be small
  OK = maximal_order(K)
  OKbmatinv = basis_mat_inv(OK, copy = false)
  basinOK = bas * QQMatrix(OKbmatinv.num) * QQFieldElem(1, OKbmatinv.den)
  deno = ZZRingElem(1)
  for i in 1:nrows(basinOK)
    for j in 1:ncols(basinOK)
      deno = lcm(deno, denominator(basinOK[i, j]))
    end
  end
   S = saturate(map_entries(FlintZZ, basinOK * deno))
  SS = S * basis_matrix(OK, copy = false)
  lllOK = lll(OK)
  N = (SS * basis_mat_inv(lllOK)).num
  lllN = lll(N)
  maybesmaller = lllN * basis_matrix(lllOK)
  return maybesmaller
end

function _improve_subfield_basis_no_lll(K, bas)
  OK = maximal_order(K)
  OKbmatinv = basis_mat_inv(OK, copy = false)
  basinOK = bas * QQMatrix(OKbmatinv.num) * QQFieldElem(1, OKbmatinv.den)
  deno = ZZRingElem(1)
  for i in 1:nrows(basinOK)
    for j in 1:ncols(basinOK)
      deno = lcm(deno, denominator(basinOK[i, j]))
    end
  end
  S = saturate(map_entries(FlintZZ, basinOK * deno))
  SS = S * basis_matrix(OK, copy = false)
  return SS
end

# Compute a primitive element given a basis of a subfield
function _subfield_primitive_element_from_basis(K::S, as::Vector{T}) where {
    S <: Union{AnticNumberField, Hecke.NfRel},
    T <: Union{nf_elem, Hecke.NfRelElem}
   }
  if isempty(as)
    return gen(K)
  end

  d = length(as)

  # First check basis elements
  i = findfirst(a -> degree(minpoly(a)) == d, as)
  if i <= d
    return as[i]
  end

  k = base_field(K)

  # Notation: cs the coefficients in a linear combination of the as, ca the dot
  # product of these vectors.
  cs = ZZRingElem[zero(ZZ) for n in 1:d]
  cs[1] = one(ZZ)
  while true
    ca = sum(c*a for (c,a) in zip(cs,as))
    if degree(minpoly(ca)) == d
      return ca
    end

    # increment the components of cs
    cs[1] += 1
    let i = 2
      while i <= d && cs[i-1] > cs[i]+1
        cs[i-1] = zero(ZZ)
        cs[i] += 1
        i += 1
      end
    end
  end
end

#As above, but for AnticNumberField type
#In this case, we can use block system to find if an element is primitive.
function _subfield_primitive_element_from_basis(K::AnticNumberField, as::Vector{nf_elem})
  if isempty(as) || degree(K) == 1
    return gen(K)
  end

  dsubfield = length(as)

  @vprintln :Subfields 1 "Sieving for primitive elements"
  # First check basis elements
  @vprintln :Subfields 1 "Sieving for primitive elements"
  # First check basis elements
  Zx = polynomial_ring(FlintZZ, "x", cached = false)[1]
  f = Zx(K.pol*denominator(K.pol))
  p, d = _find_prime(ZZPolyRingElem[f])
  #First, we search for elements that are primitive using block systems
  F = FlintFiniteField(p, d, "w", cached = false)[1]
  Ft = polynomial_ring(F, "t", cached = false)[1]
  ap = zero(Ft)
  fit!(ap, degree(K)+1)
  rt = roots(F, f)
  indices = Int[]
  for i = 1:length(as)
    b = _block(as[i], rt, ap)
    if length(b) == dsubfield
      push!(indices, i)
    end
  end

  @vprintln :Subfields 1 "Found $(length(indices)) primitive elements in the basis"
  #Now, we select the one of smallest T2 norm
  if !isempty(indices)
    a = as[indices[1]]
    I = t2(a)
    for i = 2:length(indices)
      t2n = t2(as[indices[i]])
      if t2n < I
        a = as[indices[i]]
        I = t2n
      end
    end
    @vprintln :Subfields 1 "Primitive element found"
    return a
  end

  @vprintln :Subfields 1 "Trying combinations of elements in the basis"
  # Notation: cs the coefficients in a linear combination of the as, ca the dot
  # product of these vectors.
  cs = ZZRingElem[rand(FlintZZ, -2:2) for n in 1:dsubfield]
  k = 0
  s = 1
  first = true
  a = one(K)
  I = t2(a)
  while true
    s += 1
    ca = sum(c*a for (c,a) in zip(cs,as))
    b = _block(ca, rt, ap)
    if length(b) == dsubfield
      t2n = t2(ca)
      if first
        a = ca
        I = t2n
        first = false
      elseif t2n < I
        a = ca
        I = t2n
      end
      k += 1
      if k == 5
      	@vprintln :Subfields 1 "Primitive element found"
        return a
      end
    end

    # increment the components of cs
    bb = div(s, 10)+1
    for n = 1:dsubfield
      cs[n] = rand(FlintZZ, -bb:bb)
    end
  end
end

################################################################################
#
#  Subfield
#
################################################################################

@doc raw"""
    subfield(L::NumField, elt::Vector{<: NumFieldelem};
                          isbasis::Bool = false) -> NumField, Map

The simple number field $k$ generated by the elements of `elt` over the base
field $K$ of $L$ together with the embedding $k \to L$.

If `isbasis` is `true`, it is assumed that `elt` holds a $K$-basis of $k$.
"""
function subfield(K::NumField, elt::Vector{<:NumFieldElem}; isbasis::Bool = false)
  if length(elt) == 1
    return _subfield_from_primitive_element(K, elt[1])
  end

  if isbasis
    s = _subfield_primitive_element_from_basis(K, elt)
  else
    bas = _subfield_basis(K, elt)
    s = _subfield_primitive_element_from_basis(K, bas)
  end

  return _subfield_from_primitive_element(K, s)
end

function _subfield_from_primitive_element(K::AnticNumberField, s::nf_elem)
  Qx = QQ["x"][1]
  if is_maximal_order_known(K) && s in maximal_order(K)
    OK = maximal_order(K)
    @vtime :Subfields 1 f = Qx(minpoly(representation_matrix(OK(s, false))))
  else
    # Don't return a defining polynomial with denominators
    s = denominator(s) * s
    @vtime :Subfields 1 f = minpoly(Qx, s)
  end
  L, _ = number_field(f, cached = false)
  return L, hom(L, K, s, check = false)
end

function _subfield_from_primitive_element(K, s)
  @vtime :Subfields 1 f = minpoly(s)
  L, _ = number_field(f, cached = false)
  return L, hom(L, K, s, check = false)
end

################################################################################
#
#  Fixed field
#
################################################################################

@doc raw"""
    fixed_field(K::SimpleNumField,
                sigma::Map;
                simplify::Bool = true) -> number_field, NfToNfMor

Given a number field $K$ and an automorphism $\sigma$ of $K$, this function
returns the fixed field of $\sigma$ as a pair $(L, i)$ consisting of a number
field $L$ and an embedding of $L$ into $K$.

By default, the function tries to find a small defining polynomial of $L$. This
can be disabled by setting `simplify = false`.
"""
function fixed_field(K::SimpleNumField, sigma::T; simplify::Bool = true) where {T <: NumFieldMor}
  return fixed_field(K, T[sigma], simplify = simplify)
end

#@doc raw"""
#    fixed_field(K::SimpleNumField, A::Vector{NfToNfMor}) -> number_field, NfToNfMor
#
#Given a number field $K$ and a set $A$ of automorphisms of $K$, this function
#returns the fixed field of $A$ as a pair $(L, i)$ consisting of a number field
#$L$ and an embedding of $L$ into $K$.
#
#By default, the function tries to find a small defining polynomial of $L$. This
#can be disabled by setting `simplify = false`.
#"""
function fixed_field(K::AnticNumberField, A::Vector{NfToNfMor}; simplify::Bool = true)

  autos = small_generating_set(A)
  if length(autos) == 0
    return K, id_hom(K)
  end

  if is_maximal_order_known(K)
    OK = maximal_order(K)
    if isdefined(OK, :lllO)
      k, mk = fixed_field1(K, A)
      return k, mk
    end
  end

  a = gen(K)
  n = degree(K)
  ar_mat = Vector{QQMatrix}()
  v = Vector{nf_elem}(undef, n)
  for i in 1:length(autos)
    domain(autos[i]) !== codomain(autos[i]) && error("Maps must be automorphisms")
    domain(autos[i]) !== K && error("Maps must be automorphisms of K")
    o = one(K)
    # Compute the image of the basis 1,a,...,a^(n - 1) under autos[i] and write
    # the coordinates in a matrix. This is the matrix of autos[i] with respect
    # to 1,a,...a^(n - 1).
    as = autos[i](a)
    if a == as
      continue
    end
    v[1] = o
    for j in 2:n
      o = o * as
      v[j] = o
    end
    bm = basis_matrix(v, FakeFmpqMat)
    # We have to be a bit careful (clever) since in the absolute case the
    # basis matrix is a FakeFmpqMat

    m = QQMatrix(bm.num)
    for j in 1:n
      m[j, j] = m[j, j] - bm.den # This is autos[i] - identity
    end


    push!(ar_mat, m)
  end

  if length(ar_mat) == 0
    return K, id_hom(K)
  else
    bigmatrix = hcat(ar_mat)
    k, Ker = kernel(bigmatrix, side = :left)
    bas = Vector{elem_type(K)}(undef, k)
    if simplify
      KasFMat = _improve_subfield_basis(K, Ker)
      for i in 1:k
        bas[i] = elem_from_mat_row(K, KasFMat.num, i, KasFMat.den)
      end
    else
    #KasFMat = _improve_subfield_basis_no_lll(K, Ker)
      KasFMat = FakeFmpqMat(Ker)
      Ksat = saturate(KasFMat.num)
      Ksat = lll(Ksat)
      onee = one(ZZRingElem)
      for i in 1:k
        #bas[i] = elem_from_mat_row(K, KasFMat.num, i, KasFMat.den)
        bas[i] = elem_from_mat_row(K, Ksat, i, onee)
      end
    end
  end
  return subfield(K, bas, isbasis = true)
end


function fixed_field(K::NfRel, A::Vector{T}; simplify::Bool = true) where {T <: NumFieldMor}
  autos = A

    # Everything is fixed by nothing :)
  if length(autos) == 0
    return K, id_hom(K)
  end

  F = base_field(K)
  a = gen(K)
  n = degree(K)
  ar_mat = Vector{dense_matrix_type(elem_type(F))}()
  v = Vector{elem_type(K)}(undef, n)
  for i in 1:length(autos)
    domain(autos[i]) !== codomain(autos[i]) && error("Maps must be automorphisms")
    domain(autos[i]) !== K && error("Maps must be automorphisms of K")
    o = one(K)
    # Compute the image of the basis 1,a,...,a^(n - 1) under autos[i] and write
    # the coordinates in a matrix. This is the matrix of autos[i] with respect
    # to 1,a,...a^(n - 1).
    as = autos[i](a)
    if a == as
      continue
    end
    v[1] = o
    for j in 2:n
      o = o * as
      v[j] = o
    end

    bm = basis_matrix(v)
    # In the generic case just subtract the identity
    m = bm - identity_matrix(F, degree(K))
    push!(ar_mat, m)
  end

  if length(ar_mat) == 0
    return K, id_hom(K)
  else
    bigmatrix = hcat(ar_mat)
    k, Ker = kernel(bigmatrix, side = :left)
    bas = Vector{elem_type(K)}(undef, k)
    for i in 1:k
      bas[i] = elem_from_mat_row(K, Ker, i)
    end
  end
  return subfield(K, bas, isbasis = true)
end


function fixed_field1(K::AnticNumberField, auts::Vector{NfToNfMor})

	auts_new = small_generating_set(auts)
  orderG = _order(auts)
  degree_subfield = divexact(degree(K), orderG)
  #TODO: Experiments to see if this is helpful
  #=
  if length(auts_new) == 1 && is_prime_power(degree_subfield)
    #In this case, one of the coefficients of the minpoly of gen(K)
    #over the subfield is a generator for the subfield.
    #if the given generator was not too large, also this element will be ok
		gens = auts
		if orderG != length(auts)
		  gens = closure(auts, orderG)
    end
    conjs = nf_elem[image_primitive_element(x) for x in gens]
		prim_el = sum(conjs)
		def_pol = minpoly(prim_el)
    if degree(def_pol) != degree_subfield
			conjs1 = copy(conjs)
      while degree(def_pol) != degree_subfield
				for i = 1:length(conjs)
          conjs1[i] *= conjs[i]
				end
				prim_el = sum(conjs1)
       	def_pol = minpoly(prim_el)
			end
		end
    subK = number_field(def_pol, cached = false)[1]
    mp = hom(subK, K, prim_el, check = false)
    return subK, mp
	end
=#
  OK = maximal_order(K)
  if isdefined(OK, :lllO)
    OK = lll(OK)
  end
  M = zero_matrix(FlintZZ, degree(K), degree(K)*length(auts_new))
  v = Vector{nf_elem}(undef, degree(K))
  MOK = basis_matrix(OK, copy = false)
  MOKinv = basis_mat_inv(OK, copy = false)
  for i = 1:length(auts_new)
		v[1] = one(K)
    v[2] = image_primitive_element(auts_new[i])
    for j = 3:degree(K)
      v[j] = v[j-1]*v[2]
		end
    B = basis_matrix(v, FakeFmpqMat)
    mul!(B, B, MOKinv)
    mul!(B, MOK, B)
    @assert isone(B.den)
    for i = 1:degree(K)
      B.num[i, i] -= 1
    end
		_copy_matrix_into_matrix(M, 1, (i-1)*degree(K)+1, B.num)
	end
	@vtime :Subfields 1 rk, Ker = kernel(M, side = :left)
  @assert rk == degree_subfield
  Ker = view(Ker, 1:rk, 1:degree(K))
  @vtime :Subfields 1 Ker = lll(Ker)
	#The kernel is the maximal order of the subfield.
  bas = Vector{nf_elem}(undef, degree_subfield)
	for i = 1:degree_subfield
    bas[i] = elem_from_mat_row(OK, Ker, i).elem_in_nf
	end
  return subfield(K, bas, isbasis = true)
end


################################################################################
#
#  Fixed field as relative extension
#
################################################################################

function fixed_field(K::AnticNumberField, auts::Vector{NfToNfMor}, ::Type{NfRel{nf_elem}}; simplify_subfield::Bool = true)
  F, mF = fixed_field(K, auts)
  if simplify_subfield
    F, mF1 = simplify(F, cached = false)
    mF = mF1*mF
  end
  all_auts = closure(auts, div(degree(K), degree(F)))
  Kx, x = polynomial_ring(K, "x", cached = false)
  p = prod(x-image_primitive_element(y) for y in all_auts)
  def_eq = map_coefficients(x -> haspreimage(mF, x)[2], p)
  L, gL = number_field(def_eq, cached = false, check = false)
  iso = hom(K, L, gL, image_primitive_element(mF), gen(K))
  #I also set the automorphisms...
  autsL = Vector{NfRelToNfRelMor{nf_elem, nf_elem}}(undef, length(all_auts))
  for i = 1:length(autsL)
    autsL[i] = hom(L, L, iso(image_primitive_element(all_auts[i])))
  end
  set_automorphisms!(L, autsL)
  return L, iso
end

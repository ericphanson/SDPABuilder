# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder

name = "SDPABuilder"
version = v"7.3.8"

# Collection of sources required to build SDPABuilder
sources = [
    "https://sourceforge.net/projects/sdpa/files/sdpa/sdpa_7.3.8.tar.gz" =>
    "c7541333da2f0bb2d18e90dbf758ac7cc099f3f7da3f256b284b0725f96d4117",

]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir
cd sdpa-7.3.8/
./configure --prefix=$prefix --host=$target --with-blas="${prefix}/lib/libopenblas.so" --with-lapack="${prefix}/lib/libopenblas.so"
make
make install

"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
    Linux(:i686, :glibc)
]

# The products that we will ensure are always built
products(prefix) = [
    ExecutableProduct(prefix, "", :sdpa)
]

# Dependencies that must be installed before this package can be built
dependencies = [
    "https://github.com/JuliaLinearAlgebra/OpenBLASBuilder/releases/download/v0.3.0-1/build_OpenBLAS.v0.3.0.jl"
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies)


# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder

name = "SDPABuilder"
version = v"7.3.8"

# Collection of sources required to build SDPABuilder
sources = [
    "https://sourceforge.net/projects/sdpa/files/sdpa/sdpa_7.3.8.tar.gz" =>
    "c7541333da2f0bb2d18e90dbf758ac7cc099f3f7da3f256b284b0725f96d4117",
    "./bundled"
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir
cd sdpa-7.3.8/
update_configure_scripts

for path in ${LD_LIBRARY_PATH//:/ }; do
    for file in $(ls $path/*.la); do
        echo "$file"
        baddir=$(sed -n "s|libdir=||p" $file)
        sed -i~ -e "s|$baddir|'$path'|g" $file
    done
done
if [ $target = "x86_64-apple-darwin14" ]; then
  # seems static linking requires apple's ar
  export AR=/opt/x86_64-apple-darwin14/bin/x86_64-apple-darwin14-ar
fi

## First build SDPA

patch -p1 < $WORKSPACE/srcdir/patches/shared.diff
mv configure.in configure.ac
patch -p1 < $WORKSPACE/srcdir/patches/lt_init.diff
autoreconf -i


./configure --prefix=$prefix --host=${target}  lt_cv_deplibs_check_method=pass_all \
--with-blas="-L${prefix}/lib -lcoinblas -lgfortran -lcoinmumps -lcoinmetis" \
--with-lapack="-L${prefix}/lib -lcoinlapack -lcoinmumps -lcoinmetis" \
--with-mumps-libs="-L${prefix}/lib -lcoinmumps -lcoinmetis" --with-mumps-include="-I$prefix/include/coin/ThirdParty"

make
make install

## Then build the libcxxwrap-julia wrapper

cd $WORKSPACE/srcdir
cd sdpawrap

mkdir build
cd build
if [[ $target == i686-* ]] || [[ $target == arm-* ]]; then
    export processor=pentium4
else
    export processor=x86-64
fi

cmake -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_TOOLCHAIN_FILE=/opt/$target/$target.toolchain -DSDPA_DIR=$prefix -DMUMPS_INCLUDE_DIR="$prefix/include/coin/ThirdParty" \
-DCMAKE_FIND_ROOT_PATH=$prefix -DJulia_PREFIX=$prefix  -DSDPA_LIBRARY="-lsdpa" -DCMAKE_CXX_FLAGS="-march=$processor" \
-D_GLIBCXX_USE_CXX11_ABI=1 ..
cmake --build . --config Release --target install

if [[ $target == *w64-mingw32* ]] ; then
    cp $WORKSPACE/destdir/lib/libsdpawrap.dll $WORKSPACE/destdir/bin
fi
"""

# # These are the platforms we will build for by default, unless further
# # platforms are passed in on the command line
# platforms = [
#     Linux(:i686, libc=:glibc),
#     Linux(:x86_64, libc=:glibc),
#     Linux(:aarch64, libc=:glibc),
#     Linux(:armv7l, libc=:glibc, call_abi=:eabihf),
#     MacOS(:x86_64),
#     Windows(:i686),
#     Windows(:x86_64)
# ]
# platforms = expand_gcc_versions(platforms)
# # To fix gcc4 bug in Windows
# # platforms = setdiff(platforms, [Windows(:x86_64, compiler_abi=CompilerABI(:gcc4)), Windows(:i686, compiler_abi=CompilerABI(:gcc4))])
# push!(platforms, Windows(:i686,compiler_abi=CompilerABI(:gcc6)))
# push!(platforms, Windows(:x86_64,compiler_abi=CompilerABI(:gcc6)))

# platforms are restricted by libcxxwrap-julia
# platforms = Platform[]
# _abis(p) = (:gcc7,:gcc8)
# _archs(p) = (:x86_64, :i686)
# _archs(::Type{Linux}) = (:x86_64,)
# for p in (Linux,Windows)
#     for a in _archs(p)
#         for abi in _abis(p)
#             push!(platforms, p(a, compiler_abi=CompilerABI(abi,:cxx11)))
#         end
#     end
# end
# push!(platforms, MacOS(:x86_64))

platforms = Platform[
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc6)),
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc7)),
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc8)),
    Windows(:i686, compiler_abi=CompilerABI(:gcc6, :cxx11)),
    Windows(:i686, compiler_abi=CompilerABI(:gcc7, :cxx11)),
    Windows(:i686, compiler_abi=CompilerABI(:gcc8, :cxx11)),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc6, :cxx11)),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc7, :cxx11)),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc8, :cxx11)),
    Linux(:x86_64, compiler_abi=CompilerABI(:gcc6, :cxx11)),
    Linux(:x86_64, compiler_abi=CompilerABI(:gcc7, :cxx11)),
    Linux(:x86_64, compiler_abi=CompilerABI(:gcc8, :cxx11)),
]

# The products that we will ensure are always built
products(prefix) = [
    ExecutableProduct(prefix, "sdpa", :sdpa),
    LibraryProduct(prefix, "libsdpa", :libsdpa),
    LibraryProduct(prefix, "libsdpawrap", :libsdpawrap)
]

# Dependencies that must be installed before this package can be built
dependencies = [
    "https://github.com/JuliaOpt/COINBLASBuilder/releases/download/v1.4.6-1-static/build_COINBLASBuilder.v1.4.6.jl",
    "https://github.com/JuliaOpt/COINLapackBuilder/releases/download/v1.5.6-1-static/build_COINLapackBuilder.v1.5.6.jl",
    "https://github.com/JuliaOpt/COINMetisBuilder/releases/download/v1.3.5-1-static/build_COINMetisBuilder.v1.3.5.jl",
    "https://github.com/JuliaOpt/COINMumpsBuilder/releases/download/v1.6.0-1-static/build_COINMumpsBuilder.v1.6.0.jl",
#    "./bundled/libcxxwrap/build_libcxxwrap-julia-1.0.v0.5.1.jl",
    "https://github.com/JuliaPackaging/JuliaBuilder/releases/download/v1.0.0-2/build_Julia.v1.0.0.jl",
    BinaryBuilder.InlineBuildDependency(raw"""
using BinaryProvider # requires BinaryProvider 0.3.0 or later

# Parse some basic command-line arguments
const verbose = "--verbose" in ARGS
const prefix = Prefix(get([a for a in ARGS if a != "--verbose"], 1, joinpath(@__DIR__, "usr")))
products = [
    LibraryProduct(prefix, ["libcxxwrap"], :libcxxwrap),
]

# Download binaries from hosted location
bin_prefix = "https://github.com/JuliaInterop/libcxxwrap-julia/releases/download/v0.5.1"

# Listing of files generated by BinaryBuilder:
download_info = Dict(
    Windows(:i686, compiler_abi=CompilerABI(:gcc6, :cxx11)) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.i686-w64-mingw32-gcc7-cxx11.tar.gz", "8734601b9ecb1eea38096a322aedba6021423567ed00d5a1bfd0447dd9af40e7"),
    Windows(:i686, compiler_abi=CompilerABI(:gcc7, :cxx11)) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.i686-w64-mingw32-gcc7-cxx11.tar.gz", "8734601b9ecb1eea38096a322aedba6021423567ed00d5a1bfd0447dd9af40e7"),
    Windows(:i686, compiler_abi=CompilerABI(:gcc8, :cxx11)) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.i686-w64-mingw32-gcc8-cxx11.tar.gz", "6c74b8215f0d7aa7cea0df60185bb75d48ea4cdaae58347c78666d5185dafbc8"),
    MacOS(:x86_64) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.x86_64-apple-darwin14.tar.gz", "5063cbc9389078a3d968fac92e44071a50d6102725b1abeb64ab3221bb4cd31b"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc4, :cxx11)) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.x86_64-linux-gnu-gcc7-cxx11.tar.gz", "07882f462473eccc5e2a0412f39471252e890c1427cd3a124f0371c794ded50f"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc7, :cxx11)) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.x86_64-linux-gnu-gcc7-cxx11.tar.gz", "07882f462473eccc5e2a0412f39471252e890c1427cd3a124f0371c794ded50f"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc8, :cxx11)) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.x86_64-linux-gnu-gcc8-cxx11.tar.gz", "0eafa498c6e79ee8de046e07944d06c176fb379a6e11f152d33aabc6a108b40c"),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc6, :cxx11)) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.x86_64-w64-mingw32-gcc7-cxx11.tar.gz", "ca1df9388a586c60e97a4bdfaac956614ad3097fe0f7cd57c3ea50b32de500ce"),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc7, :cxx11)) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.x86_64-w64-mingw32-gcc7-cxx11.tar.gz", "ca1df9388a586c60e97a4bdfaac956614ad3097fe0f7cd57c3ea50b32de500ce"),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc8, :cxx11)) => ("$bin_prefix/libcxxwrap-julia-1.0.v0.5.1.x86_64-w64-mingw32-gcc8-cxx11.tar.gz", "d3fdd5c84a5e2fd135f55589820a88f8c145a48047ac87041be770d31c8efed6"),
)
# Install unsatisfied or updated dependencies:
unsatisfied = any(!satisfied(p; verbose=verbose) for p in products)
dl_info = choose_download(download_info, platform_key_abi())
if dl_info === nothing && unsatisfied
    # If we don't have a compatible .tar.gz to download, complain.
    # Alternatively, you could attempt to install from a separate provider,
    # build from source or something even more ambitious here.
    error("Your platform (\\"$(Sys.MACHINE)\\", parsed as \\"$(triplet(platform_key_abi()))\\") is not supported by this package!")
end
# If we have a download, and we are unsatisfied (or the version we're
# trying to install is not itself installed) then load it up!
if unsatisfied || !isinstalled(dl_info...; prefix=prefix)
    # Download and install binaries
    install(dl_info...; prefix=prefix, force=true, verbose=verbose)
end

# Write out a deps.jl file that will contain mappings for our products
write_deps_file(joinpath(@__DIR__, "deps.jl"), products, verbose=verbose)
            """)
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies)

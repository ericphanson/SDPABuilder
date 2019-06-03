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

mv $WORKSPACE/srcdir/patches/quiet.diff .
patch -p1 < $WORKSPACE/srcdir/patches/apply_quiet.diff
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


# platforms are restricted by libcxxwrap-julia, which requires gcc7 or gcc8
# and hence will not work with the official binaries for windows (which uses gcc4)

platforms = Platform[
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc7)),
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc8)),
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
    "https://github.com/JuliaInterop/libcxxwrap-julia/releases/download/v0.5.3/build_libcxxwrap-julia-1.0.v0.5.3.jl",
    "https://github.com/JuliaPackaging/JuliaBuilder/releases/download/v1.0.0-2/build_Julia.v1.0.0.jl"    
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies)

#include <iostream>
#include <string>

// Detect architecture
#if defined(__x86_64__) || defined(_M_X64)
    #define ARCH_NAME "x86_64"
#elif defined(__aarch64__) || defined(_M_ARM64)
    #define ARCH_NAME "aarch64"
#elif defined(__arm__) || defined(_M_ARM)
    #define ARCH_NAME "arm"
#elif defined(__i386__) || defined(_M_IX86)
    #define ARCH_NAME "i386"
#elif defined(__riscv)
    #define ARCH_NAME "riscv"
#else
    #define ARCH_NAME "unknown"
#endif

// Detect OS
#if defined(__linux__)
    #define OS_NAME "linux"
#elif defined(__APPLE__)
    #define OS_NAME "darwin"
#elif defined(_WIN32)
    #define OS_NAME "windows"
#elif defined(__FreeBSD__)
    #define OS_NAME "freebsd"
#else
    #define OS_NAME "unknown"
#endif

// Detect compiler
#if defined(__clang__)
    #define COMPILER_NAME "clang"
    #define COMPILER_VERSION __clang_version__
#elif defined(__GNUC__)
    #define COMPILER_NAME "gcc"
    #define STRINGIFY(x) #x
    #define TOSTRING(x) STRINGIFY(x)
    #define COMPILER_VERSION TOSTRING(__GNUC__) "." TOSTRING(__GNUC_MINOR__) "." TOSTRING(__GNUC_PATCHLEVEL__)
#elif defined(_MSC_VER)
    #define COMPILER_NAME "msvc"
    #define COMPILER_VERSION TOSTRING(_MSC_VER)
#else
    #define COMPILER_NAME "unknown"
    #define COMPILER_VERSION "unknown"
#endif

// Detect libc
#if defined(__GLIBC__)
    #define LIBC_NAME "glibc"
#elif defined(__BIONIC__)
    #define LIBC_NAME "bionic"
#elif defined(__UCLIBC__)
    #define LIBC_NAME "uclibc"
#elif defined(__APPLE__)
    #define LIBC_NAME "libSystem"
#else
    // Could be musl or something else
    #define LIBC_NAME "other"
#endif

int main() {
    std::cout << "Cross-Compilation Example\n";
    std::cout << "=========================\n\n";

    std::cout << "Platform Information:\n";
    std::cout << "  Architecture: " << ARCH_NAME << "\n";
    std::cout << "  OS:           " << OS_NAME << "\n";
    std::cout << "  Compiler:     " << COMPILER_NAME << " " << COMPILER_VERSION << "\n";
    std::cout << "  C Library:    " << LIBC_NAME << "\n";

    std::cout << "\nPointer size: " << sizeof(void*) * 8 << " bits\n";

#if defined(__LP64__) || defined(_LP64)
    std::cout << "Data model:   LP64 (64-bit pointers and longs)\n";
#elif defined(_ILP32)
    std::cout << "Data model:   ILP32 (32-bit ints, longs, pointers)\n";
#else
    std::cout << "Data model:   Unknown\n";
#endif

    std::cout << "\nBuild successful for " << ARCH_NAME << "-" << OS_NAME << "!\n";

    return 0;
}

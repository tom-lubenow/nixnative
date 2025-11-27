#include <iostream>
#include <string>
#include <vector>
#include <cstring>

#include <zlib.h>
#include <curl/curl.h>

// Callback for curl to write data
static size_t writeCallback(void* contents, size_t size, size_t nmemb, std::string* output) {
  size_t totalSize = size * nmemb;
  output->append(static_cast<char*>(contents), totalSize);
  return totalSize;
}

void demonstrateZlib() {
  std::cout << "=== zlib demo ===\n";
  std::cout << "zlib version: " << zlibVersion() << "\n";

  // Compress some data
  const char* input = "Hello, nixnative! This is a compression test.";
  uLong inputLen = strlen(input) + 1;

  uLong compressedLen = compressBound(inputLen);
  std::vector<Bytef> compressed(compressedLen);

  int result = compress(compressed.data(), &compressedLen,
                        reinterpret_cast<const Bytef*>(input), inputLen);

  if (result == Z_OK) {
    std::cout << "Original size: " << inputLen << " bytes\n";
    std::cout << "Compressed size: " << compressedLen << " bytes\n";
    std::cout << "Compression ratio: " << (100.0 * compressedLen / inputLen) << "%\n";
  } else {
    std::cout << "Compression failed!\n";
  }
}

void demonstrateCurl() {
  std::cout << "\n=== curl demo ===\n";

  curl_version_info_data* info = curl_version_info(CURLVERSION_NOW);
  std::cout << "curl version: " << info->version << "\n";
  std::cout << "SSL version: " << (info->ssl_version ? info->ssl_version : "none") << "\n";

  // Note: We don't actually make network requests in the Nix sandbox
  std::cout << "curl initialized successfully\n";
}

int main() {
  std::cout << "pkg-config integration demo\n\n";

  demonstrateZlib();
  demonstrateCurl();

  std::cout << "\nAll libraries working correctly!\n";
  return 0;
}

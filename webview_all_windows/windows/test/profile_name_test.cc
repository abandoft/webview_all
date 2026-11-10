#include "plugin/profile_name.h"
#include <cstdio>
#include <cstdlib>
static void Check(bool value) {
  if (!value) { std::fputs("Native profile-name check failed.\n", stderr); std::abort(); }
}
using webview_all_windows::ManagedProfileName;
int main() {
  const auto first = ManagedProfileName(L"Account_1");
  Check(first && first->size() == 64);
  Check(*first == L"webview_all_6a24e64e1ca51ecae46872cdb7ee5f1a02414741b9ea8bb83471");
  Check(first == ManagedProfileName(L"account_1"));
  Check(first != ManagedProfileName(L"account_2"));
  Check(ManagedProfileName(std::wstring(64, L'a'))->size() == 64);
  Check(!ManagedProfileName(std::wstring(65, L'a')));
  Check(!ManagedProfileName(L"../Default"));
  Check(!ManagedProfileName(L""));
  Check(ManagedProfileName(L"Default") != std::optional<std::wstring>(L"Default"));
  return 0;
}

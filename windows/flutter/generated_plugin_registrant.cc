//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <printing/printing_plugin.h>
#include <quick_usb/quick_usb_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  PrintingPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PrintingPlugin"));
  QuickUsbPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("QuickUsbPlugin"));
}

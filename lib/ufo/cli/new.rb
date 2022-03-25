class Ufo::CLI
  class New < Ufo::Command
    desc "boot_hook", "Generate boot_hook"
    long_desc Help.text("new/boot_hook")
    BootHook.cli_options.each do |args|
      option(*args)
    end
    register(BootHook, "boot_hook", "boot_hook", "Generate boot_hook")

    desc "helper", "Generate helper"
    long_desc Help.text("new/helper")
    Helper.cli_options.each do |args|
      option(*args)
    end
    register(Helper, "helper", "helper", "Generate helper")

    desc "hook", "Generate hook"
    long_desc Help.text("new/hook")
    Hook.cli_options.each do |args|
      option(*args)
    end
    register(Hook, "hook", "hook", "Generate hook")
  end
end

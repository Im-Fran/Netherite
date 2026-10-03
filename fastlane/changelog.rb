# CHANGELOG.md helpers (Keep a Changelog format), shared by the Fastfile.
# Pure string functions, so `ruby fastlane/changelog.rb` checks them without fastlane.

module Changelog
  EMOJI = {
    "Added" => "✨",
    "Changed" => "🔄",
    "Deprecated" => "⚠️",
    "Removed" => "🗑️",
    "Fixed" => "🐛",
    "Security" => "🔒"
  }.freeze

  module_function

  # Body of `## [version]` up to the next `## [` heading or the link block; nil when absent.
  def section(text, version)
    match = text.match(/^## \[#{Regexp.escape(version)}\][^\n]*\n(.*?)(?=^## \[|^\[[^\]]+\]: |\z)/m)
    match && match[1].strip
  end

  # Section for a build: `## [version+build]` first, then `## [version]`, then Unreleased.
  def build_section(text, version, build = nil)
    candidates = [build && version && "#{version}+#{build}", version, "Unreleased"].compact
    candidates.lazy.map { |name| section(text, name) }.find { |body| !body.to_s.empty? }
  end

  # Markdown section → plain text for TestFlight's "What to Test".
  def release_notes(section)
    section.lines.map do |line|
      case line
      when /^### (.+)$/ then "#{EMOJI.fetch($1.strip, "•")} #{$1.strip}\n"
      when /^(\s*)[-*] (.+)$/ then "#{$1}• #{$2}\n"
      else line
      end
    end.join.strip
  end

  # Turn the Unreleased entries into a dated release and refresh the compare links.
  def stamp(text, version, date, repo_url)
    raise ArgumentError, "CHANGELOG.md already has #{version}" if section(text, version)
    previous = text[/^\[Unreleased\]: .*compare\/(.+?)\.\.\.HEAD$/, 1]
    link = previous ? "#{repo_url}/compare/#{previous}...#{version}" : "#{repo_url}/releases/tag/#{version}"
    text
      .sub(/^## \[Unreleased\]\n/, "## [Unreleased]\n\n## [#{version}] - #{date}\n")
      .sub(/^\[Unreleased\]: .*$/, "[Unreleased]: #{repo_url}/compare/#{version}...HEAD\n[#{version}]: #{link}")
  end
end

if __FILE__ == $PROGRAM_NAME
  sample = <<~MD
    # Changelog

    ## [Unreleased]

    ### Added
    - Dark mode

    ## [0.1.0] - 2026-10-03

    ### Fixed
    - A crash

    [Unreleased]: https://example.com/r/compare/0.1.0...HEAD
    [0.1.0]: https://example.com/r/releases/tag/0.1.0
  MD

  raise "unreleased" unless Changelog.section(sample, "Unreleased") == "### Added\n- Dark mode"
  raise "last section stops at links" unless Changelog.section(sample, "0.1.0") == "### Fixed\n- A crash"
  raise "build falls back to version" unless Changelog.build_section(sample, "0.1.0", 3) == "### Fixed\n- A crash"
  raise "build falls back to unreleased" unless Changelog.build_section(sample, "9.9.9", 1) == "### Added\n- Dark mode"
  with_build = sample.sub("## [0.1.0]", "## [0.1.0+2] - 2026-10-02\n\n### Fixed\n- A hang\n\n## [0.1.0]")
  raise "build section" unless Changelog.build_section(with_build, "0.1.0", "2") == "### Fixed\n- A hang"
  raise "missing" unless Changelog.section(sample, "9.9.9").nil?
  raise "notes" unless Changelog.release_notes("### Added\n- Dark mode\n  - nested") == "✨ Added\n• Dark mode\n  • nested"

  stamped = Changelog.stamp(sample, "0.2.0", "2026-11-01", "https://example.com/r")
  raise "empty unreleased" unless Changelog.section(stamped, "Unreleased") == ""
  raise "moved" unless Changelog.section(stamped, "0.2.0") == "### Added\n- Dark mode"
  raise "links" unless stamped.include?("[Unreleased]: https://example.com/r/compare/0.2.0...HEAD\n[0.2.0]: https://example.com/r/compare/0.1.0...0.2.0\n[0.1.0]:")
  puts "changelog.rb: ok"
end

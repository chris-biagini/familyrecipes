# frozen_string_literal: true

# Central registry for inline SVG icons. Returns complete <svg> strings with
# sensible defaults (fill="none", stroke="currentColor", aria-hidden="true")
# that callers can override or remove by passing nil.
#
# Collaborators:
# - All ERB templates that render icons (nav, editors, buttons)
# - config/html_safe_allowlist.yml: the .html_safe call is audited
module IconHelper
  DEFAULTS = {
    'fill' => 'none',
    'stroke' => 'currentColor',
    'stroke-linecap' => 'round',
    'stroke-linejoin' => 'round',
    'aria-hidden' => 'true'
  }.freeze

  SETTINGS_GEAR_PATH =
    'M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06' \
    'a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09' \
    'A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83' \
    '-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 ' \
    '1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 ' \
    '0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V' \
    '3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l' \
    '.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 ' \
    '0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z'

  ICONS = {
    edit: { view_box: '0 0 32 32', attrs: { 'stroke-width' => '2.5' },
            content: '<path d="M22 4l6 6-16 16H6v-6z"/><line x1="18" y1="8" x2="24" y2="14"/>' },
    plus: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '2' },
            content: '<line x1="12" y1="5" x2="12" y2="19"/>' \
                     '<line x1="5" y1="12" x2="19" y2="12"/>' },
    search: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
              content: '<circle cx="11" cy="11" r="8"/>' \
                       '<line x1="21" y1="21" x2="16.65" y2="16.65"/>' },
    settings: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
                content: %(<circle cx="12" cy="12" r="3"/><path d="#{SETTINGS_GEAR_PATH}"/>).freeze },
    book: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
            content: '<path d="M2 17 V18.5 L12 19.5"/><path d="M22 17 V18.5 L12 19.5"/>' \
                     '<path d="M2 4 C5 3.5 9 4 12 5.5 V18.5 C9 17 5 16.5 2 17 Z"/>' \
                     '<path d="M22 4 C19 3.5 15 4 12 5.5 V18.5 C15 17 19 16.5 22 17 Z"/>' \
                     '<path d="M12 5.5 V18.5"/><path d="M10.5 20 Q12 21.5 13.5 20"/>' },
    ingredients: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
                   content: '<path d="M2 10 L5.5 21 H18.5 L22 10"/>' \
                            '<line x1="1" y1="10" x2="23" y2="10"/>' \
                            '<line x1="9" y1="10" x2="16.5" y2="2.5"/>' \
                            '<line x1="11.5" y1="10" x2="19" y2="2.5"/>' \
                            '<path d="M16.5 2.5 C17 1 18.5 1 19 2.5"/>' },
    menu: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
            content: '<rect x="4" y="1" width="16" height="22"/>' \
                     '<line x1="8" y1="7" x2="16" y2="7"/>' \
                     '<line x1="8" y1="11" x2="16" y2="11"/>' \
                     '<line x1="8" y1="15" x2="16" y2="15"/>' \
                     '<line x1="8" y1="19" x2="16" y2="19"/>' },
    cart: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
            content: '<path d="M1 1h3.5l2 11h11l2.5-7H6"/>' \
                     '<circle cx="8.5" cy="19" r="2"/><circle cx="16.5" cy="19" r="2"/>' \
                     '<path d="M6.5 12h11"/>' },
    tag: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '2' },
           content: '<path d="M12 2H2v10l9.29 9.29a1 1 0 0 0 1.42 0l6.58-6.58' \
                    'a1 1 0 0 0 0-1.42L12 2Z"/><path d="M7 7h.01"/>' },
    sparkle: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '2' },
               content: '<path d="M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5' \
                        'L6 9l4.5-1.5z"/><path d="M19 13l.75 2.25L22 16l-2.25' \
                        '.75L19 19l-.75-2.25L16 16l2.25-.75z"/>' },
    apple: { view_box: '0 0 32 32', attrs: { 'stroke-width' => '2.5' },
             content: '<line x1="16" y1="9" x2="16" y2="4"/>' \
                      '<path d="M16 7c-2-2-5-2-6 0"/>' \
                      '<path d="M16 9C13 7 7 8 5 12c-2 5 0 10 3 14 2 2 4 3 6 3 ' \
                      '1 0 1.5-1 2-1s1 1 2 1c2 0 4-1 6-3 3-4 5-9 3-14-2-4-8-5-11-3z"/>' },
    scale: { view_box: '0 0 32 32', attrs: { 'stroke-width' => '2.5' },
             content: '<line x1="16" y1="3" x2="16" y2="26"/>' \
                      '<line x1="4" y1="9" x2="28" y2="9"/>' \
                      '<path d="M6 9L3 19h10L10 9"/><path d="M22 9l-3 10h10l-3-10"/>' \
                      '<line x1="10" y1="26" x2="22" y2="26"/>' },
    dice: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
            content: '<rect x="3" y="3" width="18" height="18" rx="3"/>' \
                     '<path d="M8.5 8.5h.01"/><path d="M12 12h.01"/><path d="M15.5 15.5h.01"/>' },
    check: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '2.5' },
             content: '<path d="M4 12l6 6L20 6"/>' },
    x_mark: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '2.5' },
              content: '<line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/>' },
    alert: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '2' },
             content: '<path d="M12 3L2 21h20L12 3z"/><line x1="12" y1="10" x2="12" y2="15"/>' \
                      '<path d="M12 18.5h.01"/>' },
    help: { view_box: '0 0 24 24', attrs: { 'stroke-width' => '1.8' },
            content: '<circle cx="12" cy="12" r="9"/>' \
                     '<path d="M9.5 9.5a2.5 2.5 0 0 1 5 0c0 2-2.5 2.5-2.5 4.5"/>' \
                     '<path d="M12 17.5h.01"/>' }
  }.tap { |h| h.each_value(&:freeze) }.freeze

  def icon(name, size: 24, **attrs)
    entry = ICONS.fetch(name) { raise ArgumentError, "Unknown icon: #{name}" }
    merged = build_svg_attrs(entry, size:, **attrs)
    svg_tag(merged, entry[:content])
  end

  private

  def build_svg_attrs(entry, size:, **caller_attrs)
    base = DEFAULTS.merge('viewBox' => entry[:view_box]).merge(entry[:attrs])
    apply_size(base, size)
    base.merge!(caller_attrs.transform_keys(&:to_s)).compact!
    base
  end

  def apply_size(attrs, size)
    return unless size

    attrs['width'] = size.to_s
    attrs['height'] = size.to_s
  end

  def svg_tag(attrs, content)
    attr_str = attrs.map { |k, v| %(#{k}="#{ERB::Util.html_escape(v)}") }.join(' ')
    "<svg #{attr_str}>#{content}</svg>".html_safe # rubocop:disable Rails/OutputSafety
  end
end

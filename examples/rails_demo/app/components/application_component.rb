class ApplicationComponent < Phlex::HTML
  include StyleCapsule::PhlexHelper

  private

  def helpers
    context[:helpers]
  end

  def view_context
    helpers
  end

  def raw_html(content)
    safe = content.to_s.dup
    safe.extend(Phlex::SGML::SafeObject)
    raw(safe)
  end
end

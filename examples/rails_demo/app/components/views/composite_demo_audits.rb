module Views
  module CompositeDemoAudits
    class Index < BasePage
      def initialize(current_user:, notice:, alert:, composite_demo_audits:)
        super(current_user:, notice:, alert:)
        @composite_demo_audits = composite_demo_audits
      end

      def view_template
        with_layout(title: "Composite PK Audits") do
          section(class: "card") do
            h1 { "Composite Primary Key Demo Audits" }
            p(class: "muted") { "Audit records with composite identity and partition-aligned keys." }
          end
          section(class: "card") do
            table do
              thead { tr { th { "ID" }; th { "Partition" }; th { "Action" }; th { "Version" }; th { "Auditable" }; th { "At" } } }
              tbody do
                @composite_demo_audits.each do |audit|
                  tr do
                    td { raw_html helpers.link_to(helpers.id_to_param(audit.id), helpers.composite_demo_audit_path(audit)) }
                    td { audit.partition_key.to_s }
                    td { audit.action.to_s }
                    td { audit.version.to_s }
                    td { "#{audit.auditable_type}##{audit.auditable_id}" }
                    td { audit.created_at&.strftime("%Y-%m-%d %H:%M").to_s }
                  end
                end
              end
            end
          end
        end
      end
    end

    class Show < BasePage
      def initialize(current_user:, notice:, alert:, composite_demo_audit:)
        super(current_user:, notice:, alert:)
        @composite_demo_audit = composite_demo_audit
      end

      def view_template
        with_layout(title: "Composite Audit") do
          section(class: "card") do
            h1 { "Composite Audit #{helpers.id_to_param(@composite_demo_audit.id)}" }
            pre { @composite_demo_audit.attributes.to_json }
            div(class: "actions") { raw_html helpers.link_to("Back", helpers.composite_demo_audits_path, class: "btn") }
          end
        end
      end
    end
  end
end

Rails.application.configure do
# Configure Solid Events
config.solid_events.connects_to = { database: { writing: :solid_events } }
end

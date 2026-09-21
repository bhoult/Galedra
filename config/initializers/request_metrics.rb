# frozen_string_literal: true

# Stage 40: record how long each controller action took, how many statements it
# issued, and how often it was asked for. Off unless LEDGER_REQUEST_METRICS is
# set (see RequestMetrics and .env.example).
#
# The subscriptions are always attached and cost a comparison each when the flag
# is off; attaching them conditionally at boot would mean a restart to turn the
# thing on, and the whole point is to be able to turn it on when something is
# slow.
#
# `sql.active_record` fires inside the request, so the counter is a thread-local
# reset by `start_processing`. `process_action` fires after the response, which
# is where the row is written: the one extra statement a slow request pays for
# is paid after the reader has their page.
ActiveSupport::Notifications.subscribe("start_processing.action_controller") do
  RequestMetrics.start_request if RequestMetrics.enabled?
end

ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
  RequestMetrics.count_statement unless payload[:name] == "SCHEMA" || payload[:cached]
end

ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, start, finish, _id, payload|
  RequestMetrics.record(
    action: "#{payload[:controller].to_s.sub(/Controller\z/, '').underscore}##{payload[:action]}",
    method: payload[:method].to_s,
    status: payload[:status],
    duration_ms: (finish - start) * 1000,
    db_ms: payload[:db_runtime],
    view_ms: payload[:view_runtime],
    request_id: payload[:request]&.request_id
  )
end

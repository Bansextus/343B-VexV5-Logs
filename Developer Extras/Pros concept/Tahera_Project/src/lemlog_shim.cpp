#include "LemLog/logger/Helper.hpp"
#include "LemLog/logger/Sink.hpp"

#include <algorithm>

namespace logger {
namespace {
std::list<Sink*>& sink_list() {
    static std::list<Sink*> sinks;
    return sinks;
}

int level_value(Level level) {
    switch (level) {
        case Level::DEBUG:
            return 0;
        case Level::INFO:
            return 1;
        case Level::WARN:
            return 2;
        case Level::ERROR:
            return 3;
        default:
            return 1;
    }
}

bool list_contains(const std::list<std::string>& list, const std::string& value) {
    return std::find(list.begin(), list.end(), value) != list.end();
}
} // namespace

void log(Level level, const std::string& topic, const std::string& message) {
    auto& sinks = sink_list();
    for (auto it = sinks.begin(); it != sinks.end();) {
        Sink* sink = *it;
        const SinkStatus status = sink->send(level, topic, message);
        if (status == SinkStatus::ERROR) {
            it = sinks.erase(it);
            continue;
        }
        ++it;
    }
}

Sink::Sink(std::string name)
    : m_name(std::move(name)) {
    sink_list().push_back(this);
}

Sink::~Sink() {
    sink_list().remove(this);
}

void Sink::addToAllowList(const std::string& topic) {
    if (!list_contains(m_allowList, topic)) {
        m_allowList.push_back(topic);
    }
}

void Sink::removeFromAllowList(const std::string& topic) {
    m_allowList.remove(topic);
}

void Sink::addToBlockedList(const std::string& topic) {
    if (!list_contains(m_blockedList, topic)) {
        m_blockedList.push_back(topic);
    }
}

void Sink::removeFromBlockedList(const std::string& topic) {
    m_blockedList.remove(topic);
}

void Sink::setLoggingLevel(Level level) {
    m_minLevel = level;
}

const std::string& Sink::getName() const& {
    return m_name;
}

SinkStatus Sink::send(Level level, const std::string& topic, const std::string& message) {
    if (level_value(level) < level_value(m_minLevel)) {
        return SinkStatus::OK;
    }

    if (!m_allowList.empty() && !list_contains(m_allowList, topic)) {
        return SinkStatus::OK;
    }

    if (list_contains(m_blockedList, topic)) {
        return SinkStatus::OK;
    }

    return write(level, topic, message);
}

} // namespace logger

logger::Helper::Helper(const std::string& topic)
    : m_topic(topic) {}

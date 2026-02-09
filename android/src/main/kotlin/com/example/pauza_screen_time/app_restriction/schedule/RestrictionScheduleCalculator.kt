package com.example.pauza_screen_time.app_restriction.schedule

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

internal class RestrictionScheduleCalculator {

    fun isInSessionNow(
        config: RestrictionScheduleConfig,
        now: ZonedDateTime = ZonedDateTime.now(ZoneId.systemDefault()),
    ): Boolean {
        if (!isConfigValid(config)) return false

        val windows = buildCandidateWindows(config, now.toLocalDate())
        return windows.any { (start, end) ->
            !now.isBefore(start) && now.isBefore(end)
        }
    }

    fun nextBoundary(
        config: RestrictionScheduleConfig,
        now: ZonedDateTime = ZonedDateTime.now(ZoneId.systemDefault()),
    ): RestrictionScheduleBoundary? {
        if (!isConfigValid(config)) return null

        val windows = buildCandidateWindows(config, now.toLocalDate())
        val activeWindow = windows.firstOrNull { (start, end) ->
            !now.isBefore(start) && now.isBefore(end)
        }

        if (activeWindow != null) {
            return RestrictionScheduleBoundary(
                type = RestrictionScheduleBoundaryType.END,
                at = activeWindow.second,
            )
        }

        val nextStart = windows
            .asSequence()
            .map { it.first }
            .filter { it.isAfter(now) }
            .minOrNull() ?: return null

        return RestrictionScheduleBoundary(
            type = RestrictionScheduleBoundaryType.START,
            at = nextStart,
        )
    }

    fun isConfigValid(config: RestrictionScheduleConfig): Boolean {
        if (!config.enabled || !hasAnySchedule(config)) {
            return false
        }
        return isScheduleShapeValid(config)
    }

    fun hasAnySchedule(config: RestrictionScheduleConfig): Boolean {
        return config.schedules.isNotEmpty()
    }

    fun isScheduleShapeValid(config: RestrictionScheduleConfig): Boolean {
        if (config.schedules.isEmpty()) {
            return true
        }

        val splitByDay = mutableMapOf<Int, MutableList<Pair<Int, Int>>>()
        for (schedule in config.schedules) {
            if (!isEntryValid(schedule)) {
                return false
            }
            for (day in schedule.daysOfWeekIso) {
                val dayWindows = splitByDay.getOrPut(day) { mutableListOf() }
                if (schedule.endMinutes > schedule.startMinutes) {
                    dayWindows += schedule.startMinutes to schedule.endMinutes
                } else {
                    dayWindows += schedule.startMinutes to (24 * 60)
                    val nextDay = if (day == 7) 1 else day + 1
                    val nextDayWindows = splitByDay.getOrPut(nextDay) { mutableListOf() }
                    nextDayWindows += 0 to schedule.endMinutes
                }
            }
        }

        return splitByDay.values.all { windows ->
            val sorted = windows.sortedBy { it.first }
            sorted.zipWithNext().all { (left, right) ->
                right.first >= left.second
            }
        }
    }

    private fun buildCandidateWindows(
        config: RestrictionScheduleConfig,
        referenceDate: LocalDate,
    ): List<Pair<ZonedDateTime, ZonedDateTime>> {
        val zoneId = ZoneId.systemDefault()
        val windows = mutableListOf<Pair<ZonedDateTime, ZonedDateTime>>()

        for (schedule in config.schedules) {
            for (offsetDays in -1L..8L) {
                val date = referenceDate.plusDays(offsetDays)
                val isoDayOfWeek = date.dayOfWeek.isoDay()
                if (!schedule.daysOfWeekIso.contains(isoDayOfWeek)) continue

                val startTime = LocalTime.of(
                    schedule.startMinutes / 60,
                    schedule.startMinutes % 60,
                )
                val endTime = LocalTime.of(
                    schedule.endMinutes / 60,
                    schedule.endMinutes % 60,
                )

                val startAt = date.atTime(startTime).atZone(zoneId)
                val endDate = if (schedule.endMinutes <= schedule.startMinutes) {
                    date.plusDays(1)
                } else {
                    date
                }
                val endAt = endDate.atTime(endTime).atZone(zoneId)

                windows += startAt to endAt
            }
        }

        return windows.sortedBy { it.first.toInstant() }
    }

    private fun isEntryValid(schedule: RestrictionScheduleEntry): Boolean {
        return schedule.daysOfWeekIso.isNotEmpty() &&
            schedule.daysOfWeekIso.all { it in 1..7 } &&
            schedule.startMinutes in 0 until 24 * 60 &&
            schedule.endMinutes in 0 until 24 * 60 &&
            schedule.startMinutes != schedule.endMinutes
    }

    private fun DayOfWeek.isoDay(): Int = when (this) {
        DayOfWeek.MONDAY -> 1
        DayOfWeek.TUESDAY -> 2
        DayOfWeek.WEDNESDAY -> 3
        DayOfWeek.THURSDAY -> 4
        DayOfWeek.FRIDAY -> 5
        DayOfWeek.SATURDAY -> 6
        DayOfWeek.SUNDAY -> 7
    }
}

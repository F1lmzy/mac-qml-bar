#pragma once
#include <QPainterPath>
#include <QRect>

inline QRect pillFrame(const QRect &screen, const QSize &size, int topOffset) {
    return QRect(screen.x() + (screen.width() - size.width()) / 2,
                 screen.y() + topOffset, size.width(), size.height());
}

inline bool pillContains(const QSizeF &size, const QPointF &point, qreal cornerRadius = 20) {
    if (point.x() < 0 || point.y() < 0 ||
        point.x() >= size.width() || point.y() >= size.height()) return false;
    QPainterPath shape;
    const qreal radius = qBound(0.0, cornerRadius, qMin(size.width(), size.height()) / 2);
    shape.addRoundedRect(QRectF(QPointF(), size), radius, radius);
    return shape.contains(point);
}

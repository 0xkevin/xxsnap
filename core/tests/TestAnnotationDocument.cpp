#include <QtTest/QtTest>

#include "snipory/core/annotation/AnnotationDocument.h"

class TestAnnotationDocument final : public QObject {
    Q_OBJECT

private slots:
    void undoHidesLastShape()
    {
        snipory::core::AnnotationDocument document;
        const snipory::core::AnnotationStyle style;

        document.addShape(snipory::core::ShapeAnnotation::rectangle(QRect(10, 20, 100, 80), style));
        document.addShape(snipory::core::ShapeAnnotation::ellipse(QRect(30, 40, 60, 50), style));
        document.undo();

        QCOMPARE(document.shapes().size(), 1);
    }

    void replacingShapeCreatesUndoableHistoryEntry()
    {
        snipory::core::AnnotationDocument document;
        snipory::core::AnnotationStyle style;
        style.strokeWidth = 3;

        document.addShape(snipory::core::ShapeAnnotation::rectangle(QRect(10, 20, 100, 80), style));

        style.cornerRadius = 12;
        QVERIFY(document.replaceShape(0, snipory::core::ShapeAnnotation::rectangle(QRect(12, 22, 120, 90), style)));

        QCOMPARE(document.shapes().size(), 1);
        QCOMPARE(document.shapes().at(0).rect, QRect(12, 22, 120, 90));
        QCOMPARE(document.shapes().at(0).style.cornerRadius, 12);

        document.undo();
        QCOMPARE(document.shapes().at(0).rect, QRect(10, 20, 100, 80));

        document.redo();
        QCOMPARE(document.shapes().at(0).style.cornerRadius, 12);
    }
};

QTEST_MAIN(TestAnnotationDocument)
#include "TestAnnotationDocument.moc"

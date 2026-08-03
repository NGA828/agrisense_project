from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('diagnosis', '0005_outbreakalert'),
    ]

    operations = [
        migrations.AddField(
            model_name='diagnosis',
            name='inference_engine',
            field=models.CharField(default='unknown', max_length=50),
        ),
        migrations.AddField(
            model_name='diagnosis',
            name='used_trained_model',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='diagnosis',
            name='model_version',
            field=models.CharField(blank=True, default='', max_length=100),
        ),
        migrations.AddField(
            model_name='diagnosis',
            name='model_label',
            field=models.CharField(blank=True, default='', max_length=200),
        ),
        migrations.AddField(
            model_name='diagnosis',
            name='alternatives',
            field=models.JSONField(blank=True, default=list),
        ),
    ]

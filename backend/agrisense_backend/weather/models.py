from django.db import models

class WeatherData(models.Model):
    location_name = models.CharField(max_length=200)
    latitude = models.FloatField()
    longitude = models.FloatField()
    temperature = models.FloatField()
    feels_like = models.FloatField(default=0)
    humidity = models.IntegerField()
    wind_speed = models.FloatField()
    condition = models.CharField(max_length=100, default='')
    rain_probability = models.IntegerField(default=0)
    description = models.CharField(max_length=100, default='')
    farming_advice = models.TextField(default='')
    fetched_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.location_name} - {self.temperature}°C"

    class Meta:
        db_table = 'weather_data'
        ordering = ['-fetched_at']
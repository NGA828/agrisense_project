from django.db import models
from django.conf import settings

class Announcement(models.Model):
    TARGET_CHOICES = (
        ('all', 'All Users'),
        ('farmers', 'Farmers Only'),
        ('dealers', 'Dealers Only'),
    )
    
    title = models.CharField(max_length=200)
    content = models.TextField()
    target_audience = models.CharField(max_length=20, choices=TARGET_CHOICES, default='all')
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='announcements')
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return self.title
    
    class Meta:
        db_table = 'announcement'
        ordering = ['-created_at']

from django.db import models


class AIModel(models.Model):
    """Audit metadata for validated model releases.

    Runtime artifact paths remain deployment configuration (environment/
    mounted secrets), rather than admin-editable filesystem paths. Diagnosis
    rows persist the version actually used for each inference.
    """
    name = models.CharField(max_length=100)
    version = models.CharField(max_length=20)
    accuracy = models.DecimalField(max_digits=5, decimal_places=2)
    created_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)

    def __str__(self):
        return f'{self.name} {self.version}'

    class Meta:
        db_table = 'ai_model'
        
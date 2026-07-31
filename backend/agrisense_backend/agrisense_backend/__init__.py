import pymysql

# Make PyMySQL act as MySQLdb so Django's MySQL backend works without mysqlclient
pymysql.install_as_MySQLdb()

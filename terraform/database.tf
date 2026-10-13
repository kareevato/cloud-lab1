resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "-_"
}

resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "aws_db_subnet_group" "db" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project}-db"
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t4g.micro"
  db_name                = "appdb"
  username               = "dbuser"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true
  apply_immediately      = true
}

# Секрети для застосунку: SecureString у SSM Parameter Store, читаються інстансом через IAM-роль
resource "aws_ssm_parameter" "database_url" {
  name  = "${local.param_prefix}/database_url"
  type  = "SecureString"
  value = "postgresql://${aws_db_instance.postgres.username}:${urlencode(random_password.db.result)}@${aws_db_instance.postgres.endpoint}/${aws_db_instance.postgres.db_name}"
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "${local.param_prefix}/jwt_secret"
  type  = "SecureString"
  value = random_password.jwt.result
}

resource "aws_ssm_parameter" "admin_username" {
  name  = "${local.param_prefix}/admin_username"
  type  = "String"
  value = var.admin_username
}

resource "aws_ssm_parameter" "admin_password" {
  name  = "${local.param_prefix}/admin_password"
  type  = "SecureString"
  value = var.admin_password
}

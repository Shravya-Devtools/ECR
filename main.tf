provider "aws" {
  region  = "us-east-1"  # AWS region for Account B
  profile = "accountB_profile"  # AWS profile for Account B

  assume_role {
    role_arn     = "arn:aws:iam::[AccountB-ID]:role/TerraformExecutionRole"  # Role to assume in Account B
    session_name = "TerraformSession"
  }
}

# ECS Task Role in Account B (allows ECS to assume role to pull images from Account A)
resource "aws_iam_role" "ecs_task_role" {
  name               = "ecsTaskRole"
  assume_role_policy = jsonencode({
    "Version"   = "2012-10-17",
    "Statement" = [
      {
        "Effect"   = "Allow",
        "Principal" = {
          "Service" = "ecs-tasks.amazonaws.com"
        },
        "Action"   = "sts:AssumeRole"
      }
    ]
  })
}

# ECS Execution Role in Account B (grants ECS permissions to interact with AWS services)
resource "aws_iam_role" "ecs_execution_role" {
  name               = "ecsExecutionRole"
  assume_role_policy = jsonencode({
    "Version"   = "2012-10-17",
    "Statement" = [
      {
        "Effect"   = "Allow",
        "Principal" = {
          "Service" = "ecs-tasks.amazonaws.com"
        },
        "Action"   = "sts:AssumeRole"
      }
    ]
  })
}

# ECS Task Definition (using image from Account A's ECR)
resource "aws_ecs_task_definition" "ecs_task" {
  family                   = "my-ecs-task-definition"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions    = jsonencode([{
    name      = "my-container"
    image     = "741846357014.dkr.ecr.us-east-1.amazonaws.com/my-ecr-repository:v1.0.0"  # ECR image in Account A
    memory    = 512
    cpu       = 256
    essential = true
  }])
  network_mode = "awsvpc"
}

# ECS Service to run ECS Task
resource "aws_ecs_service" "ecs_service" {
  name            = "my-ecs-service"
  cluster         = "NewCluster"  # ECS cluster ID in Account B
  task_definition = aws_ecs_task_definition.ecs_task.arn
  desired_count   = 1
}

# Lambda function using image from ECR in Account A
resource "aws_lambda_function" "my_lambda_function" {
  function_name = "my-lambda-function"
  role          = aws_iam_role.ecs_execution_role.arn
  image_uri     = "741846357014.dkr.ecr.us-east-1.amazonaws.com/my-ecr-repository:v1.0.0"
  package_type  = "Image"
}

# IAM Policy allowing ECS and Lambda to pull images from ECR in Account A
resource "aws_iam_policy" "ecr_access_policy" {
  name        = "ECRAccessPolicy"
  description = "Allow ECS and Lambda to pull images from Account A's ECR"
  policy      = jsonencode({
    "Version"   = "2012-10-17",
    "Statement" = [
      {
        "Effect"   = "Allow",
        "Action"   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories"
        ],
        "Resource" = "arn:aws:ecr:us-east-1:741846357014:repository/my-ecr-repository"
      }
    ]
  })
}

# Attach the policy to ECS and Lambda execution roles in Account B
resource "aws_iam_role_policy_attachment" "ecs_ecr_access" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecr_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_ecr_access" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecr_access_policy.arn
}

# Output ECS Service and Lambda function names
output "ecs_service_name" {
  value = aws_ecs_service.ecs_service.name
}

output "lambda_function_name" {
  value = aws_lambda_function.my_lambda_function.function_name
}
